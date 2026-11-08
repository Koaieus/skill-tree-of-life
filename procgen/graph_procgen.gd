@tool
class_name GraphProcgen
extends RefCounted

## Pipeline runner. Static — no state beyond what flows through `generate`.
## Stages:
##   1. Poisson-disk sample positions inside the [ShapeMask] (with anchors).
##   2. Delaunay triangulate the points; that's our planar candidate edge set.
##   3. Prune to MST + a `connectivity`-controlled share of shortest extras
##      (stages 1–3 run as [ProcgenTopology]).
##   4. Cluster-assign an [ArchetypePolicy] per node (target-driven BFS-grow).
##   5. Per node, roll a budget ([BudgetPolicy]) and draw modifiers from the
##      node's archetype + universal [StatPool]s (spend-until-broke v4 draw,
##      [ProcgenModifierRoller]) after rolling its subtype ([ProcgenSubtypeRoll]).
##   6. Instantiate SkillNodes + Edges under the [Graph], with the post-loop
##      addon pass ([ProcgenAddonDraw]) between.
##
## Returns a Dictionary `{nodes: Array[SkillNode], starting_nodes:
## Array[SkillNode], starters: Array[StartingPoint], blockers:
## Array[Dictionary], config: GraphProcgenConfig}` — `config` is the copy
## generation resolved (the caller's is never written to); `starting_nodes[i]` is the SkillNode that landed on
## `config.starting.starting_points[i]`, for the caller to wire as entity cores, and
## each `blockers` entry is `{"node": SkillNode, "size": int, "prune_seed":
## int, "footprint": Array[SkillNode], "stake_level": int}` (`size` being a
## [EntityFactory.BlockerSize] int, `prune_seed` the loot-book prune's seed,
## `footprint` the bonus nodes the blocker also owns, `stake_level` the
## pre-stake in 1..3) for the caller to hand to `spawn_blocker`.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BLOCKER_NODE_SCENE := preload("res://skill_node/blocker_node.tscn")

## Arbitrary offset mixed into the main `rng.seed` to derive [member
## _place_blocker_indices]'s own RNG stream. Blocker placement has to
## run BEFORE the per-node content loop (so the loop can pick the right node
## scene), which would otherwise consume draws off the shared `rng` ahead of
## every other roll — silently reshuffling what a given seed generates
## everywhere else. A same-seed-derived-but-independent stream keeps blocker
## placement itself deterministic while leaving the main stream untouched.
const _BLOCKER_RNG_SALT := 0x8477
## Salt for [member PlacementContext.scene_rng] — scene placements draw
## off their own derived stream so the main `rng` is byte-identical with or
## without them.
const _SCENE_RNG_SALT := 0x3300
## Salt for the Dormant Core face roll ([method GraphProcgenBlockers.roll_faces]):
## its own stream, so faces on or off leave every blocker draw above it intact.
const _FACE_RNG_SALT := 0xFACE
## Salt for the node-subtype placement roll, for the same reason as the
## two above and one more: the roll happens mid-loop, per node, so off the
## shared `rng` every modifier draw after it would shift — both goldens would
## churn on any `base_chance` retune and a placement change would be
## indistinguishable from a content change.
const _SUBTYPE_RNG_SALT := 0x5B17
## Salt for the addon placement pass's own stream (see [method ProcgenAddonDraw.run]).
const _ADDON_RNG_SALT := 0xADD0

## Poisson-disk auto-scale sizing: the disc area a ShapeMask needs to hold
## `node_count` points at spacing `min_dist`. ONE MEASURED constant (area per
## point Bridson achieves), set just above the measured curve so the flood exhausts
## at the `max_points` cap. Re-check `test_procgen_sizing.gd` before retuning.
## See docs/domain/procgen-sizing.md
const _POISSON_AREA_PER_POINT := 1.60

## Relative slack in [method node_count_for_area] so it stays an exact inverse
## of [method target_area_for_node_count] under float rounding. Far below any
## meaningful count difference; see that method.
const _ROUND_TRIP_EPSILON := 1e-9


## Area (in world units²) a ShapeMask needs so Poisson can comfortably place
## `node_count` points at `min_dist` spacing. Shape-agnostic — pair with a
## shape's own area→extent conversion (e.g. [method CircularShapeMask.size_for]).
static func target_area_for_node_count(node_count: int, min_dist: float) -> float:
	return float(maxi(1, node_count)) * min_dist * min_dist * _POISSON_AREA_PER_POINT


## Inverse of [method target_area_for_node_count]: how many points Poisson is
## expected to place in a region of `area` at `min_dist` spacing. Used by
## consumers that need to predict a count from a region size instead of the
## other way around (e.g. the "how many nodes does this stamp cover").
##
## `_ROUND_TRIP_EPSILON` exists because `floor` on a multiply-then-divide is
## not exact: `target_area_for_node_count(n)` fed straight back here can land
## a few ULPs under `n` and floor to `n - 1`. Whether it does depends on the
## bit pattern of `_POISSON_AREA_PER_POINT` — 1.60 happens to round-trip
## cleanly and the 1.799773 it replaced did not, which is luck, not a
## contract. Nudging up by a relative epsilon makes the inverse exact for
## every constant without changing any genuinely fractional prediction.
static func node_count_for_area(area: float, min_dist: float) -> int:
	if min_dist <= 0.0:
		return 0
	var exact := maxf(0.0, area) / (min_dist * min_dist * _POISSON_AREA_PER_POINT)
	return int(floor(exact * (1.0 + _ROUND_TRIP_EPSILON)))


## Convenience for circular regions (stamps): expected node count within a
## disc of `radius` at `min_dist` spacing.
static func node_count_for_radius(radius: float, min_dist: float) -> int:
	return node_count_for_area(PI * radius * radius, min_dist)


## When `progress_cb` is a valid Callable, `generate` becomes a coroutine —
## it emits progress in [0, 1] with a short label between stages and yields
## one `process_frame` per emit so the caller's UI can repaint. Pass an empty
## Callable (the default) for the synchronous fast path used by tests and
## headless tooling.
##
## Callers that pass `progress_cb` MUST `await` the call; the synchronous
## path returns the Dictionary directly.
static func generate(
		config: GraphProcgenConfig,
		graph: Graph,
		progress_cb: Callable = Callable(),
) -> Dictionary:
	assert(config != null, "GraphProcgen.generate: null config")
	assert(graph != null, "GraphProcgen.generate: null graph")
	assert(config.shape.shape_mask != null, "GraphProcgen.generate: config.shape.shape_mask is null")

	# The caller resolved the sentinel already — `GameSession.start` for a
	# real run, an explicit seed for a test or an editor preview. Generation is
	# not a resolution site: a seed nobody recorded is a run nobody can replay.
	# The resolve call behind the assert is the release-build floor (asserts are
	# debug-only) and is a no-op on any already-resolved seed.
	assert(config.seed != 0,
			"GraphProcgen.generate: unresolved seed sentinel — resolve it once up front "
			+ "via GameSession.start()/ensure_started() (or RunConfig.resolve_seed) (#457)")
	var rng := RandomNumberGenerator.new()
	rng.seed = RunConfig.resolve_seed(config.seed)

	# Generation resolves on its OWN copy and returns it as `"config"`; the
	# caller's config object is never written to (see resolve_config). Copy
	# before the first yield, so no frame ever runs on the caller's object.
	config = ProcgenTopology.resolve_config(config)
	await _emit_progress(progress_cb, 0.02, "Preparing shape")
	await _emit_progress(progress_cb, 0.05, "Sampling positions")
	# Stages 1–3 in one phase: starter assembly, Poisson sample, Delaunay +
	# prune. The two labels above and below bracket it — the phase never
	# touches the callback.
	var topo := ProcgenTopology.run(config, rng)
	var starters := topo.starters
	if not topo.ok:
		return {
				"nodes": [] as Array[SkillNode],
				"starting_nodes": [] as Array[SkillNode],
				"starters": starters,
				"config": config,
		}
	var positions := topo.positions
	await _emit_progress(progress_cb, 0.25, "Connecting edges")
	var edge_pairs := topo.edge_pairs
	await _emit_progress(progress_cb, 0.30, "Planning clusters")
	var type_assignments: PackedInt32Array
	if not config.content.archetypes.is_empty():
		type_assignments = _assign_archetypes(positions, edge_pairs, config, rng)
	else:
		# No archetypes → no clustering source. Leave every node unassigned;
		# the per-node loop skips content for a -1 assignment.
		type_assignments.resize(positions.size())
		type_assignments.fill(-1)

	# Post-clustering territory stamps. Override archetype assignments
	# for nodes inside each stamp's region — before building the placement
	# context so the updated assignments flow into guaranteed placements too.
	if not config.content.archetype_stamps.is_empty():
		_apply_archetype_stamps(positions, edge_pairs, type_assignments, config)

	# Pre-roll pass: GuaranteedPlacements decorate nodes with role tags.
	# starting_points were placed first into the position list (by index).
	await _emit_progress(progress_cb, 0.40, "Placing guarantees")
	var starter_indices := PackedInt32Array()
	for k in starters.size():
		starter_indices.append(k)
	var placement_ctx := _build_placement_context(
			positions, edge_pairs, type_assignments, starter_indices, config, rng)
	for placement in config.content.guaranteed_placements:
		if placement != null:
			placement.apply(placement_ctx)

	# Removable-blocker placement. Computed on INDICES before the
	# per-node loop so a blocked node can be instantiated from
	# [constant _BLOCKER_NODE_SCENE] (the boulder visual) rather than
	# swapped in afterwards — the edges and self-loops below wire `nodes` by
	# reference, so a node can't be replaced once added. Eligibility mirrors
	# the old post-loop pass: never a starter core (indices < starters.size())
	# nor an authored-scene node (placement_ctx.scenes[i] != null) —
	# plus, never a node inside the core safe radius
	# (blocker_min_hops_from_core).
	#
	# Deliberately rides its OWN derived RNG, not the shared `rng` stream:
	# running this before the per-node content loop (needed so the loop can
	# pick the right scene) would otherwise shift every subsequent draw off
	# `rng` — silently changing what a given seed generates for the rest of
	# `generate` (archetype rolls, modifier rolls, self-loops, ...). Deriving
	# from `config.seed` keeps the main stream byte-for-byte identical to
	# before blockers existed.
	var blocker_rng := RandomNumberGenerator.new()
	blocker_rng.seed = rng.seed + _BLOCKER_RNG_SALT
	var blocker_sizes := _place_blocker_indices(
			positions.size(), placement_ctx, config, blocker_rng)
	# One prune seed per placement, drawn HERE rather than at spawn
	# time because the level scene is re-run on every peer — the loot-book
	# prune is reproduced, not received, so an unseeded roll there would hand
	# two peers different offers off the same relic (multiplayer-sync.md).
	# Same dedicated stream as the placement above, so the main `rng` is
	# untouched and a given seed still generates the same map.
	var blocker_seeds: Dictionary[int, int] = {}
	for idx: int in blocker_sizes:
		blocker_seeds[idx] = blocker_rng.randi()
	# Bonus-node footprints, drawn LAST off the same stream so every
	# draw above — the cores, the sizes, the prune seeds — is byte-for-byte
	# what an earlier seed produced. Appending is the whole reason this is a
	# separate pass rather than a branch inside the placement loop.
	var blocker_footprints := _place_blocker_footprints(
			blocker_sizes, placement_ctx, config, blocker_rng)
	# Pre-stake rolls, drawn after the footprints off the same stream
	# and for the same reason: appended last, so every draw above is what an
	# earlier seed produced. Always two draws per blocker, chance or not, so
	# a later pass appended here is stable across a chance retune too.
	var blocker_stakes := _roll_blocker_stakes(blocker_sizes, config.blockers, blocker_rng)
	var face_rng := RandomNumberGenerator.new()
	face_rng.seed = rng.seed + _FACE_RNG_SALT
	var blocker_faces := config.blockers.roll_faces(blocker_sizes.keys(), face_rng)

	await _emit_progress(progress_cb, 0.45, "Rolling content")
	var nodes: Array[SkillNode] = []
	# INT-archetype nodes only — the eligible pool for the spell-grant
	# distribution, run as a single post-loop pass once every node exists
	# (see GraphProcgenSpellGrants.distribute; it needs the full pool size to
	# compute the level's grant budget, not a per-node decision).
	var int_nodes: Array[SkillNode] = []
	# Every non-authored-scene node: the addon pass's draw pool.
	var addon_eligible: Array[SkillNode] = []
	# Subtype placement — its own derived stream, plus the two things
	# that must be computed ONCE per generate(): the resolved default (D14) and
	# D13's per-(archetype, subtype) drawability lookup.
	var subtype_rng := RandomNumberGenerator.new()
	subtype_rng.seed = rng.seed + _SUBTYPE_RNG_SALT
	var default_subtype: NodeSubtype = null
	var subtype_drawable: Dictionary = {}
	if config.content != null:
		default_subtype = config.content.resolved_default_subtype()
		subtype_drawable = ProcgenSubtypeRoll.build_drawability(config.content)
	# Yield ~10 times across the per-node loop so the bar moves smoothly
	# without paying a frame per node. With 500 nodes that's every ~50.
	@warning_ignore("integer_division")
	var yield_every := maxi(1, positions.size() / 10)
	for i in positions.size():
		var sn: SkillNode
		var authored_scene: PackedScene = placement_ctx.scenes[i]
		if authored_scene != null:
			# An authored-scene node is PURE: the scene IS the content.
			# Procgen sets its position and nothing else — no archetype, no
			# budget, no modifier roll, no rolled addons, no radius stamp (the
			# scene's authored radius stands), never a blocker (eligibility
			# excluded it), never in the spell-grant pool.
			sn = authored_scene.instantiate()
			sn.position = positions[i]
			if not placement_ctx.role_tags[i].is_empty():
				sn.set_meta("role_tags", placement_ctx.role_tags[i].duplicate())
			graph.add_skill_node(sn)
			nodes.append(sn)
			continue
		if blocker_sizes.has(i):
			sn = _BLOCKER_NODE_SCENE.instantiate()
		else:
			sn = _SKILL_NODE_SCENE.instantiate()
		sn.position = positions[i]
		var archetype_id: StringName = &""
		var archetype_color: Color = Color.WHITE
		var archetype_forbid: Array[StringName] = []
		var archetype_primary_stat: StringName = &""
		var archetype_resource: Archetype = null
		if type_assignments[i] >= 0:
			var policy: ArchetypePolicy = config.content.archetypes[type_assignments[i]]
			if policy != null and policy.archetype != null:
				archetype_id = policy.id
				archetype_color = policy.archetype.color
				archetype_forbid = policy.forbid_tags
				archetype_primary_stat = policy.archetype.primary_stat
				archetype_resource = policy.archetype
		if archetype_id != &"":
			var fp := {"archetype": archetype_id, "primary_stat": archetype_primary_stat}
			if not placement_ctx.role_tags[i].is_empty():
				fp["role_tags"] = placement_ctx.role_tags[i].duplicate()
			var role_tags: Array = placement_ctx.role_tags[i]
			var budget := 0
			if config.content.budget_policy != null:
				budget = config.content.budget_policy.compute_budget(
						archetype_id, positions[i], role_tags, rng)
			fp["budget"] = budget
			# One draw per archetype-bearing node whenever any subtype is
			# authored — a constant draw count keeps a `base_chance` retune
			# from shifting another node's roll. The budget-0 else branch gets
			# no subtype (nor any content).
			var node_subtype := ProcgenSubtypeRoll.run(
					config.content.subtypes, archetype_primary_stat,
					subtype_drawable, default_subtype, subtype_rng)
			# Radius follows the rolled budget; an authored scene never
			# reaches this branch, so its own radius stands.
			_stamp_radius(sn, config.topology.radius_for_budget(budget))
			if config.content.modifier_pool_set != null:
				sn.authored_modifiers = ProcgenModifierRoller.run(
						config.content.modifier_pool_set, config.content.weight_profiles,
						archetype_id, archetype_primary_stat, archetype_forbid,
						positions[i], i, budget, rng, fp, node_subtype,
						config.content.universal_share,
						config.content.multiply_fuse_floor)
			sn.set_meta("procgen_footprint", fp)
			# Stamps NodeVisualsComposite's archetype_tint (persistent type
			# identity, rim/sensed-outline colour). Owner colour stays free to
			# drive the entity_tint channel via SkillNode.
			sn.base_type_color = archetype_color
			# The archetype's own emblem shape (docs/domain/skillnode-emblem.md) —
			# every archetype carries one now, so this always stamps.
			sn.archetype = archetype_resource
			# The node's second identity — the visuals child reads its tint and
			# emissive tier. Always the resolved value, never null.
			sn.subtype = node_subtype
			sn.set_meta("archetype", archetype_id)
			if archetype_primary_stat != &"":
				sn.set_meta("primary_stat", archetype_primary_stat)
			# Persist role tags for downstream inspection / debug overlays.
			if not placement_ctx.role_tags[i].is_empty():
				sn.set_meta("role_tags", placement_ctx.role_tags[i].duplicate())
		else:
			# No archetype → no budget → the uniform default (budget 0 path).
			_stamp_radius(sn, config.topology.radius_for_budget(0))
		graph.add_skill_node(sn)
		addon_eligible.append(sn)
		if GraphProcgenSpellGrants.is_eligible_node(archetype_primary_stat):
			int_nodes.append(sn)
		nodes.append(sn)
		if i > 0 and i % yield_every == 0:
			# 0.45 → 0.92 over the per-node loop.
			var frac: float = 0.45 + 0.47 * (float(i) / float(positions.size()))
			await _emit_progress(progress_cb, frac, "Rolling content")

	# Own derived stream (the blocker pass's precedent): retuning the addon
	# density never shifts the modifier rolls on the main `rng`.
	var addon_rng := RandomNumberGenerator.new()
	addon_rng.seed = rng.seed + _ADDON_RNG_SALT
	ProcgenAddonDraw.run(addon_eligible, nodes.size(), config, addon_rng)

	GraphProcgenSpellGrants.distribute(
			int_nodes, config.content.spell_grant_pool, config.content.spell_grant_ratio, rng)

	await _emit_progress(progress_cb, 0.95, "Wiring edges")
	for pair in edge_pairs:
		graph.add_edge(nodes[pair.x], nodes[pair.y])
	
	# Self-loops — floor-guaranteed staged draw without replacement.
	# Tier 1 draws floor(N × p1) nodes uniformly from all generated nodes
	# (partial Fisher-Yates, no replacement); tier k draws floor(K_{k-1} × p_k)
	# from the previous tier's set. Each tier then does ONE Bernoulli on the
	# fractional remainder to add +1 (floor + 0-or-1), and a node that hits
	# tier k gets exactly k self-loops. The number of tier knobs IS the cap
	# (4) — raising it later means adding a tier-5 knob. Cores are NOT
	# excluded from the tier-1 pool — a self-loop on a core is a defining
	# launch condition by design.
	var tier_rates := [
			config.topology.self_loop_tier1_rate,
			config.topology.self_loop_tier2_rate,
			config.topology.self_loop_tier3_rate,
			config.topology.self_loop_tier4_rate,
	]
	var pool: Array = nodes.duplicate()
	for tier in tier_rates.size():
		var rate: float = tier_rates[tier]
		var count := int(floor(pool.size() * rate))
		if rng.randf() < pool.size() * rate - float(count):
			count += 1
		count = mini(count, pool.size())
		# Partial Fisher-Yates: the first `count` of the shuffled pool.
		for i in count:
			var j := i + rng.randi() % (pool.size() - i)
			var tmp: Variant = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		# Each tier UPGRADES its draw by one loop: a tier-1 node gets 1
		# self-loop, a tier-2 node 2 (1 from tier 1 + this), ... tier-k nodes
		# end with exactly k loops — add_edge is called k times total per
		# tier-k node across the cascade. Cap = 4 follows from 4 knobs.
		for i in count:
			var node := pool[i] as SkillNode
			graph.add_edge(node, node)
		pool = pool.slice(0, count)

	# Starting points were seeded first into Poisson; they occupy positions[0..n).
	var starting_nodes: Array[SkillNode] = []
	for i in min(starters.size(), nodes.size()):
		starting_nodes.append(nodes[i])

	# Removable-blocker placements, rebuilt from the index→size
	# map sampled before the per-node loop. `blocker_sizes` iterates in
	# insertion (tier) order — small, then medium, then large — matching the
	# old post-loop pass's result order, so result shape (`{node, size}`) is
	# unchanged.
	var blockers: Array[Dictionary] = []
	for idx: int in blocker_sizes:
		# The footprint crosses as NODES, not indices: `spawn_blocker` is
		# the consumer and it force-allocates them, so resolving here keeps the
		# index basis (which only `generate` can map) out of the level scene.
		var footprint: Array[SkillNode] = []
		for f: int in blocker_footprints.get(idx, PackedInt32Array()):
			footprint.append(nodes[f])
		blockers.append({
			"node": nodes[idx],
			"size": int(blocker_sizes[idx]),
			"prune_seed": int(blocker_seeds[idx]),
			"footprint": footprint,
			"stake_level": int(blocker_stakes.get(idx, 1)),
			"face": (blocker_faces.get(idx, {}) as Dictionary).get("face"),
			"face_seed": int((blocker_faces.get(idx, {}) as Dictionary).get("seed", 0)),
		})

	await _emit_progress(progress_cb, 1.0, "Done")
	return {
		"nodes": nodes,
		"starting_nodes": starting_nodes,
		"starters": starters,
		"blockers": blockers,
		"config": config,
	}


## Calls `progress_cb` (if valid) and yields one process_frame so the caller's
## UI can repaint. No-op + no yield when callback is empty — keeps synchronous
## callers truly synchronous.
static func _emit_progress(progress_cb: Callable, frac: float, label: String) -> void:
	if not progress_cb.is_valid():
		return
	progress_cb.call(frac, label)
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		await (tree as SceneTree).process_frame



# ── Clustering: target-driven BFS-grow ───────────────────────────────────


## Cluster assignment. Returns an int per position, indexing into
## [GraphProcgenContent.archetypes]. Algorithm (BFS-grow; see the clustering
## section of docs/domain/procgen.md):
##  1. Compute target node count per archetype from target_ratio shares.
##  2. Per archetype, sample cluster sizes from cluster_size_weights until
##     Σ sizes ≥ target_count. Build a flat plan list.
##  3. Sort plans largest-first so big clusters claim space first.
##  4. Place each plan's seed greedily (random first seed, then
##     farthest-from-existing-seeds among unclaimed nodes).
##  5. BFS-grow each cluster through the pruned graph adjacency up to its
##     target_size, claiming only unclaimed neighbours.
##  6. Any unclaimed leftovers: graph-BFS outward until a claimed neighbour
##     is found, inherit its archetype.
##  7. Per-node cluster_jitter reroll using the assigned archetype's policy.
static func _assign_archetypes(
		positions: Array[Vector2],
		edge_pairs: Array[Vector2i],
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> PackedInt32Array:
	var n := positions.size()
	var out := PackedInt32Array()
	out.resize(n)
	for i in n:
		out[i] = -1
	if n == 0 or config.content.archetypes.is_empty():
		return out

	# Step 1: target counts per archetype (normalised target_ratio).
	var total_ratio := 0.0
	for a in config.content.archetypes:
		if a != null:
			total_ratio += maxf(0.0, a.target_ratio)
	if total_ratio <= 0.0:
		# All-zero: uniform fallback.
		for k in config.content.archetypes.size():
			if config.content.archetypes[k] != null:
				total_ratio += 1.0
	var target_counts: Array[int] = []
	target_counts.resize(config.content.archetypes.size())
	var assigned_so_far := 0
	for k in config.content.archetypes.size():
		var policy: ArchetypePolicy = config.content.archetypes[k]
		var ratio := 0.0 if policy == null else maxf(0.0, policy.target_ratio)
		if total_ratio > 0.0 and ratio == 0.0 and policy != null:
			ratio = 1.0  # uniform-fallback path
		var tc := int(round(float(n) * ratio / total_ratio)) if total_ratio > 0.0 else 0
		target_counts[k] = tc
		assigned_so_far += tc
	# Reconcile rounding so Σ target_counts == n (drop / add to the largest).
	var diff := n - assigned_so_far
	if diff != 0:
		var biggest_idx := 0
		for k in target_counts.size():
			if target_counts[k] > target_counts[biggest_idx]:
				biggest_idx = k
		target_counts[biggest_idx] = maxi(0, target_counts[biggest_idx] + diff)

	# Step 2: build flat cluster plan list.
	# Each plan = {archetype_idx, target_size}. Use Vector2i (x=archetype, y=size).
	var plans: Array[Vector2i] = []
	for k in config.content.archetypes.size():
		var policy: ArchetypePolicy = config.content.archetypes[k]
		if policy == null:
			continue
		var remaining := target_counts[k]
		while remaining > 0:
			var size := policy.sample_cluster_size(rng)
			size = mini(size, remaining)
			if size <= 0:
				break
			plans.append(Vector2i(k, size))
			remaining -= size

	# Step 3: sort plans largest-first.
	plans.sort_custom(func(a, b): return a.y > b.y)

	# Adjacency from pruned edges.
	var adj: Array[PackedInt32Array] = []
	for i in n:
		adj.append(PackedInt32Array())
	for e in edge_pairs:
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)

	# Steps 4–5: place seed, then BFS-grow each plan.
	var seeds: Array[int] = []
	for plan in plans:
		var seed_idx := _pick_seed_node(positions, out, seeds, rng)
		if seed_idx < 0:
			break  # no unclaimed nodes left
		out[seed_idx] = plan.x
		seeds.append(seed_idx)
		# BFS-grow from this seed up to plan.y nodes.
		var claimed := 1
		var frontier: Array[int] = [seed_idx]
		while claimed < plan.y and not frontier.is_empty():
			var next_frontier: Array[int] = []
			for node in frontier:
				for nb in adj[node]:
					if out[nb] != -1:
						continue
					out[nb] = plan.x
					next_frontier.append(nb)
					claimed += 1
					if claimed >= plan.y:
						break
				if claimed >= plan.y:
					break
			frontier = next_frontier

	# Step 6: fallback for unclaimed nodes — graph-BFS to nearest claimed.
	# (Running counts maintained so ArchetypeBalancer, if enabled, can react.)
	var counts := PackedInt32Array()
	counts.resize(config.content.archetypes.size())
	var total_assigned := 0
	for i in n:
		if out[i] != -1 and out[i] < counts.size():
			counts[out[i]] += 1
			total_assigned += 1
	var balancer: ArchetypeBalancer = config.content.archetype_balancer
	var use_balancer := balancer != null and balancer.enabled
	for i in n:
		if out[i] != -1:
			continue
		var found := _bfs_to_first_claimed(i, out, adj)
		if found != -1:
			out[i] = found
		else:
			# Disconnected & nothing claimed reachable.
			out[i] = (balancer.pick(config.content.archetypes, counts, total_assigned, rng)
					if use_balancer else _pick_archetype_by_ratio(config.content.archetypes, rng))
		if out[i] >= 0 and out[i] < counts.size():
			counts[out[i]] += 1
			total_assigned += 1

	# Step 7: cluster_jitter reroll per archetype.
	for i in n:
		var policy: ArchetypePolicy = config.content.archetypes[out[i]] if out[i] >= 0 and out[i] < config.content.archetypes.size() else null
		if policy != null and rng.randf() < policy.cluster_jitter:
			var prev := out[i]
			out[i] = (balancer.pick(config.content.archetypes, counts, total_assigned, rng)
					if use_balancer else _pick_archetype_by_ratio(config.content.archetypes, rng))
			if use_balancer and prev != out[i]:
				if prev >= 0 and prev < counts.size():
					counts[prev] -= 1
				if out[i] >= 0 and out[i] < counts.size():
					counts[out[i]] += 1

	return out


static func _pick_seed_node(
		positions: Array[Vector2],
		assignments: PackedInt32Array,
		existing_seeds: Array[int],
		rng: RandomNumberGenerator,
) -> int:
	# Greedy farthest-from-existing-seeds among unclaimed. First seed is random.
	var n := positions.size()
	if existing_seeds.is_empty():
		# Random unclaimed.
		var unclaimed: Array[int] = []
		for i in n:
			if assignments[i] == -1:
				unclaimed.append(i)
		if unclaimed.is_empty():
			return -1
		return unclaimed[rng.randi() % unclaimed.size()]
	var best_idx := -1
	var best_min_sq := -1.0
	for i in n:
		if assignments[i] != -1:
			continue
		var min_sq := INF
		for s in existing_seeds:
			var d := positions[i].distance_squared_to(positions[s])
			if d < min_sq:
				min_sq = d
		if min_sq > best_min_sq:
			best_min_sq = min_sq
			best_idx = i
	return best_idx


static func _bfs_to_first_claimed(
		start: int,
		assignments: PackedInt32Array,
		adj: Array[PackedInt32Array],
) -> int:
	# Returns the archetype index of the first claimed node reachable from
	# `start` via BFS, or -1 if none.
	var seen := {}
	seen[start] = true
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for nb in adj[current]:
			if seen.has(nb):
				continue
			seen[nb] = true
			if assignments[nb] != -1:
				return assignments[nb]
			queue.append(nb)
	return -1


static func _pick_archetype_by_ratio(
		archetypes: Array[ArchetypePolicy],
		rng: RandomNumberGenerator,
) -> int:
	var total := 0.0
	for a in archetypes:
		if a != null:
			total += maxf(0.0, a.target_ratio)
	if total <= 0.0:
		return rng.randi() % archetypes.size()
	var r := rng.randf() * total
	for k in archetypes.size():
		var a := archetypes[k]
		if a == null:
			continue
		r -= maxf(0.0, a.target_ratio)
		if r <= 0.0:
			return k
	return archetypes.size() - 1


# ── Territory stamping ─────────────────────────────────────────────


static func _apply_archetype_stamps(
		positions: Array[Vector2],
		edge_pairs: Array[Vector2i],
		type_assignments: PackedInt32Array,
		config: GraphProcgenConfig,
) -> void:
	var n := positions.size()
	for stamp in config.content.archetype_stamps:
		if stamp == null:
			continue
		if stamp.archetype_idx < 0 or stamp.archetype_idx >= config.content.archetypes.size():
			push_warning("ArchetypeStamp: archetype_idx %d out of range (archetypes has %d entries); skipping."
				% [stamp.archetype_idx, config.content.archetypes.size()])
			continue

		match stamp.mode:
			ArchetypeStamp.RegionMode.EUCLIDEAN:
				var rsq := stamp.radius * stamp.radius
				if rsq <= 0.0:
					continue
				for i in n:
					if positions[i].distance_squared_to(stamp.position) <= rsq:
						type_assignments[i] = stamp.archetype_idx

			ArchetypeStamp.RegionMode.TOPOLOGICAL:
				if stamp.seed_node_index < 0 or stamp.seed_node_index >= n:
					push_warning("ArchetypeStamp: seed_node_index %d out of range (0..%d); skipping."
						% [stamp.seed_node_index, n - 1])
					continue
				var indices := _region_indices_from_hops(stamp.seed_node_index, stamp.max_hops, edge_pairs, n)
				for i in indices:
					type_assignments[i] = stamp.archetype_idx


## BFS flood: returns all node indices reachable from [param start] in at most
## [param max_hops] hops (including [param start] itself). Uses [param edge_pairs]
## to build the adjacency list lazily. Shared by [method _apply_archetype_stamps]
## (stamp region) and available for any future non-PlacementContext BFS needs.
static func _region_indices_from_hops(
		start: int,
		max_hops: int,
		edge_pairs: Array[Vector2i],
		node_count: int,
) -> PackedInt32Array:
	var out := PackedInt32Array()
	if start < 0 or start >= node_count or max_hops < 0:
		return out
	var adj: Array[PackedInt32Array] = []
	for i in node_count:
		adj.append(PackedInt32Array())
	for e in edge_pairs:
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)
	var seen := {start: true}
	var frontier: Array[int] = [start]
	out.append(start)
	var hops := 0
	while hops < max_hops and not frontier.is_empty():
		var next: Array[int] = []
		for n_idx in frontier:
			for nb in adj[n_idx]:
				if seen.has(nb):
					continue
				seen[nb] = true
				next.append(nb)
				out.append(nb)
		frontier = next
		hops += 1
	return out


# ── GuaranteedPlacement pre-pass ─────────────────────────────────────────


static func _build_placement_context(
		positions: Array[Vector2],
		edge_pairs: Array[Vector2i],
		type_assignments: PackedInt32Array,
		starter_indices: PackedInt32Array,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> PlacementContext:
	var ctx := PlacementContext.new()
	ctx.positions = positions
	ctx.edge_pairs = edge_pairs
	ctx.type_assignments = type_assignments
	ctx.starter_indices = starter_indices
	ctx.config = config
	ctx.rng = rng
	# Adjacency.
	var adj: Array[PackedInt32Array] = []
	for i in positions.size():
		adj.append(PackedInt32Array())
	for e in edge_pairs:
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)
	ctx.adjacency = adj
	# Per-node empty role-tag arrays + null scene slots.
	var rt: Array = []
	rt.resize(positions.size())
	for i in positions.size():
		rt[i] = [] as Array[StringName]
	ctx.role_tags = rt
	var sc: Array = []
	sc.resize(positions.size())
	ctx.scenes = sc
	# Derived stream, same reason as the blocker pass below: scene
	# draws never shift the main `rng`, and every peer reproduces the picks.
	ctx.scene_rng = RandomNumberGenerator.new()
	ctx.scene_rng.seed = rng.seed + _SCENE_RNG_SALT
	return ctx


# ── Removable-blocker placement ───────────────────────────────────


## Pre-loop pass picking which node INDICES get a removable blocker, per size
## tier (`floor(node_count / denom)`, sampled without replacement). Excludes
## starter cores, authored-scene nodes and the safe hop-ball around any starter.
## The basis is the AUTHORED `node_count`. Uses its own derived rng.
## See docs/domain/procgen-v4.md
static func _place_blocker_indices(
		positions_count: int,
		ctx: PlacementContext,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> Dictionary:
	var out: Dictionary = {}
	var scenes: Array = ctx.scenes
	var starter_count := ctx.starter_indices.size()
	# Core safe radius: union of the hop-balls around every starter.
	var too_close := {}
	if config.blockers.blocker_min_hops_from_core > 0:
		for s in ctx.starter_indices:
			for n in ctx.nodes_within_hops(s, config.blockers.blocker_min_hops_from_core):
				too_close[n] = true
	var eligible: Array[int] = []
	for i in positions_count:
		if i < starter_count:
			continue
		if i < scenes.size() and scenes[i] != null:
			continue
		if too_close.has(i):
			continue
		eligible.append(i)
	if eligible.is_empty():
		if not too_close.is_empty():
			push_warning("GraphProcgen: no blocker-eligible node outside the %d-hop core safe radius — placing none" % config.blockers.blocker_min_hops_from_core)
		return out

	# Small → medium → large (most numerous first). Each tier partial-Fisher-
	# Yates-shuffles the front of the remaining pool and slices the winners off,
	# so no node can be picked by two tiers.
	var tiers: Array = [
		[config.blockers.blocker_per_small, EntityFactory.BlockerSize.SMALL],
		[config.blockers.blocker_per_medium, EntityFactory.BlockerSize.MEDIUM],
		[config.blockers.blocker_per_large, EntityFactory.BlockerSize.LARGE],
	]
	for tier in tiers:
		var denom: int = tier[0]
		if denom <= 0:
			continue
		# Clamp positive-but-too-small denominators up to the safety floor
		# Denom 1..4 would otherwise place a blocker on nearly every
		# node, so a joker authoring `1` still gets `5`.
		denom = maxi(denom, GraphProcgenBlockers.MIN_BLOCKER_PER)
		# node_count, not positions_count/eligible.size() — see docstring.
		var count := int(floor(float(config.topology.node_count) / float(denom)))
		count = mini(count, eligible.size())
		for i in count:
			var j := i + rng.randi() % (eligible.size() - i)
			var tmp: int = eligible[i]
			eligible[i] = eligible[j]
			eligible[j] = tmp
			out[eligible[i]] = int(tier[1])
		eligible = eligible.slice(count)
	return out



## The pre-stake per placed blocker: a chain of two draws against the
## tier's chance — P(stake 2), then P(stake 3 | stake 2) — so with chance `p`
## the split is `1−p : p(1−p) : p²`. Draws are ALWAYS consumed (both of them,
## whatever the chance) so the stream stays aligned across a retune. 1..3 by
## construction; a stake past the core's ceiling raises the ceiling
## ([method EntityFactory.set_procgen_stake]).
static func _roll_blocker_stakes(
	blocker_sizes: Dictionary, blockers: GraphProcgenBlockers,
	blocker_rng: RandomNumberGenerator
) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	for idx: int in blocker_sizes:
		var chance := blockers.stake_chance(int(blocker_sizes[idx])) if blockers != null else 0.0
		var stake := 1
		var first := blocker_rng.randf()
		var second := blocker_rng.randf()
		if chance > 0.0 and first < chance:
			stake = 2
			if second < chance:
				stake = 3
		out[idx] = stake
	return out


## Grow each placed blocker's bonus-node FOOTPRINT: randomized frontier growth
## (connected by construction) over eligible nodes, in tier order. Returns index ->
## PackedInt32Array of bonus-node indices (core excluded); short of candidates a
## blocker shrinks rather than steals a claim.
## See docs/domain/procgen-v4.md
static func _place_blocker_footprints(
		blocker_sizes: Dictionary,
		ctx: PlacementContext,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> Dictionary:
	var out: Dictionary = {}
	if blocker_sizes.is_empty():
		return out
	var mods := config.blockers
	# Nothing authored anywhere → skip the walk (and every draw it would make),
	# so a preset that opts out generates exactly what a pre-footprint seed did.
	var wants_footprints := false
	for size: int in [0, 1, 2]:
		if mods.footprint_range(size).y > 0:
			wants_footprints = true
			break
	if not wants_footprints:
		return out

	var scenes: Array = ctx.scenes
	var starter_count := ctx.starter_indices.size()
	var too_close := {}
	if mods.blocker_min_hops_from_core > 0:
		for st in ctx.starter_indices:
			for n in ctx.nodes_within_hops(st, mods.blocker_min_hops_from_core):
				too_close[n] = true
	# Every blocker core is claimed up front — a core placed later in the tier
	# order must not be swallowed by an earlier blocker's footprint.
	var claimed: Dictionary[int, bool] = {}
	for idx: int in blocker_sizes:
		claimed[idx] = true

	for idx: int in blocker_sizes:
		var span := mods.footprint_range(int(blocker_sizes[idx]))
		var want := rng.randi_range(span.x, span.y)
		if want <= 0:
			continue
		var grown := PackedInt32Array()
		# The live frontier: eligible, unclaimed nodes adjacent to the blocker's
		# current territory. Rebuilt incrementally as the walk grows.
		var frontier: Array[int] = []
		var in_frontier: Dictionary[int, bool] = {}
		var push_neighbours := func(n: int) -> void:
			for nb: int in ctx.adjacency[n]:
				if claimed.has(nb) or in_frontier.has(nb):
					continue
				if nb < starter_count:
					continue
				if nb < scenes.size() and scenes[nb] != null:
					continue
				if too_close.has(nb):
					continue
				in_frontier[nb] = true
				frontier.append(nb)
		push_neighbours.call(idx)
		while grown.size() < want and not frontier.is_empty():
			var pick := rng.randi() % frontier.size()
			var node_idx: int = frontier[pick]
			# Swap-remove: order in `frontier` is not meaningful, and the draw
			# above already randomized the choice.
			frontier[pick] = frontier[frontier.size() - 1]
			frontier.resize(frontier.size() - 1)
			in_frontier.erase(node_idx)
			claimed[node_idx] = true
			grown.append(node_idx)
			push_neighbours.call(node_idx)
		if not grown.is_empty():
			out[idx] = grown
	return out



# ── Addon roll (second pass) ─────────────────────────────────────────────


## Procgen writes only the authored `base_*` pair (`radius` / `inner_radius`
## are derived, stake growth on top — see SkillNode). The inner disk keeps a
## constant 8px ring, today's 32/24, so the fill scales with the node.
const _INNER_RING_PX := 8.0


static func _stamp_radius(sn: SkillNode, base_radius: float) -> void:
	sn.base_radius = base_radius
	sn.base_inner_radius = base_radius - _INNER_RING_PX
