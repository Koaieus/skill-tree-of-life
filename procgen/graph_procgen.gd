@tool
class_name GraphProcgen
extends RefCounted

## Pipeline runner. Static — no state beyond what flows through `generate`.
## Stages:
##   1. Poisson-disk sample positions inside the [ShapeMask] (with anchors).
##   2. Delaunay triangulate the points; that's our planar candidate edge set.
##   3. Prune to MST + a `connectivity`-controlled share of shortest extras
##      (stages 1–3 run as [ProcgenTopology]).
##   4. Cluster-assign an [ArchetypePolicy] per node (target-driven BFS-grow,
##      [ProcgenArchetypeStamper]).
##   4b. Placement pre-pass ([ProcgenPlacement]): guaranteed placements and
##       removable-blocker planning (indices, seeds, footprints, stakes, faces).
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

## Salt for the node-subtype placement roll, for the same reason as the
## placement phase's salted streams and one more: the roll happens mid-loop,
## per node, so off the
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
	# Stage 4 plus the territory-stamp pass in one phase. The label above
	# brackets it — the phase never touches the callback.
	var type_assignments := ProcgenArchetypeStamper.run(
			positions, edge_pairs, config, rng)

	# Pre-roll placement pass: GuaranteedPlacements decorate nodes with role
	# tags, then removable-blocker placement is planned (on INDICES, before the
	# per-node loop — the edges and self-loops below wire `nodes` by reference,
	# so a node can't be replaced once added; the phase picks the scene from
	# the index map). Progress stays here; the phase never touches the
	# callback. Its body and draw order are unchanged, so a given seed still
	# generates the same map.
	await _emit_progress(progress_cb, 0.40, "Placing guarantees")
	var starter_indices := PackedInt32Array()
	for k in starters.size():
		starter_indices.append(k)
	var placement := ProcgenPlacement.run(
			positions, edge_pairs, type_assignments, starter_indices, config, rng)
	var placement_ctx := placement.ctx
	var blocker_sizes := placement.blocker_sizes
	var blocker_seeds := placement.blocker_seeds
	var blocker_footprints := placement.blocker_footprints
	var blocker_stakes := placement.blocker_stakes
	var blocker_faces := placement.blocker_faces

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
			ProcgenPlacement._stamp_radius(sn, config.topology.radius_for_budget(budget))
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
			ProcgenPlacement._stamp_radius(sn, config.topology.radius_for_budget(0))
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
