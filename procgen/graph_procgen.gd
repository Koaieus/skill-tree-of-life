@tool
class_name GraphProcgen
extends RefCounted

## Pipeline runner. Static — no state beyond what flows through `generate`.
## Stages:
##   1. Poisson-disk sample positions inside the [ShapeMask] (with anchors).
##   2. Delaunay triangulate the points; that's our planar candidate edge set.
##   3. Prune to MST + a `connectivity`-controlled share of shortest extras.
##   4. Cluster-assign an [ArchetypePolicy] per node (target-driven BFS-grow).
##   5. Per node, roll a budget ([BudgetPolicy]) and draw modifiers from the
##      archetype-sliced [ModifierPoolSet] (phased v3 draw).
##   6. Instantiate SkillNodes + Edges under the [Graph].
##
## Returns a Dictionary `{nodes: Array[SkillNode], starting_nodes:
## Array[SkillNode]}` — `starting_nodes[i]` is the SkillNode that landed on
## `config.starting_points[i]`, for the caller to wire as entity cores.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")

## Poisson-disk auto-scale sizing (issue #164). The area a ShapeMask needs to
## comfortably hold `node_count` points at spacing `min_dist` is derived from
## two factors, kept separate so each is individually inspectable/testable:
##   - `_POISSON_PACKING_EFFICIENCY`: Bridson-style rejection sampling reaches
##     roughly this fraction of the theoretical hexagonal packing density
##     (hex cell area at spacing d is `(√3/2)·d²`; dividing by efficiency
##     gives the area Poisson actually needs per point).
##   - `_POISSON_SAFETY_MARGIN`: extra headroom on top of that so the
##     active-list random walk doesn't bail out near the shape's rim before
##     reaching `node_count` (boundary rejection wastes tries at the edge).
## Combined they give ~1.8× the raw hex-cell area per point. #163 (territory
## stamping) depends on this ratio staying accurate — a stamp's node count is
## *predicted* from it, not resampled locally — so don't retune without
## re-checking test_procgen_sizing.gd.
const _POISSON_PACKING_EFFICIENCY := 0.69
const _POISSON_SAFETY_MARGIN := 1.434
const _HEX_CELL_AREA_FACTOR := 0.866  # √3 / 2


## Area (in world units²) a ShapeMask needs so Poisson can comfortably place
## `node_count` points at `min_dist` spacing. Shape-agnostic — pair with a
## shape's own area→extent conversion (e.g. [method CircularShapeMask.size_for]).
static func target_area_for_node_count(node_count: int, min_dist: float) -> float:
	var area_per_point := _HEX_CELL_AREA_FACTOR / _POISSON_PACKING_EFFICIENCY * _POISSON_SAFETY_MARGIN
	return float(maxi(1, node_count)) * min_dist * min_dist * area_per_point


## Inverse of [method target_area_for_node_count]: how many points Poisson is
## expected to place in a region of `area` at `min_dist` spacing. Used by
## consumers that need to predict a count from a region size instead of the
## other way around (e.g. #163's "how many nodes does this stamp cover").
static func node_count_for_area(area: float, min_dist: float) -> int:
	if min_dist <= 0.0:
		return 0
	var area_per_point := _HEX_CELL_AREA_FACTOR / _POISSON_PACKING_EFFICIENCY * _POISSON_SAFETY_MARGIN
	return int(floor(maxf(0.0, area) / (min_dist * min_dist * area_per_point)))


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
	assert(config.shape_mask != null, "GraphProcgen.generate: config.shape_mask is null")

	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed if config.seed != 0 else randi()

	var min_dist := 2.0 * config.node_radius + config.node_padding
	await _emit_progress(progress_cb, 0.02, "Preparing shape")
	# Auto-size the shape mask so Poisson can fit node_count at the requested
	# spacing without under-filling. See _POISSON_PACKING_EFFICIENCY /
	# _POISSON_SAFETY_MARGIN above for the derivation.
	if config.shape_mask != null and config.shape_mask.auto_scale:
		var target_area := target_area_for_node_count(config.node_count, min_dist)
		config.shape_mask.size_for(target_area, min_dist * 4.0)
	# Now that the mask is sized, propagate its outer radius to any radial
	# fields/profiles that opted in (outer_radius ≤ 0).
	_propagate_mask_radius(config)
	# Final ordered starter list = manual entries first, then any random anchors
	# we place. Caller reads back via `starting_nodes` in the same order, so
	# manual vs. random can be told apart by index.
	var starters: Array[StartingPoint] = []
	for sp in config.starting_points:
		if sp != null:
			starters.append(sp)
	_place_random_starters(starters, config, rng)

	var anchors: Array[Vector2] = []
	for sp in starters:
		anchors.append(sp.position)
	await _emit_progress(progress_cb, 0.05, "Sampling positions")
	var positions := PoissonDiskSampler.sample(
			config.shape_mask, min_dist, config.node_count,
			anchors, rng)
	if positions.is_empty():
		push_warning("GraphProcgen: sampler produced no points")
		return {
				"nodes": [] as Array[SkillNode],
				"starting_nodes": [] as Array[SkillNode],
				"starters": starters,
		}

	await _emit_progress(progress_cb, 0.25, "Connecting edges")
	var edge_pairs := _triangulate_and_prune(positions, config.connectivity)
	await _emit_progress(progress_cb, 0.30, "Planning clusters")
	var type_assignments: PackedInt32Array
	if not config.archetypes.is_empty():
		type_assignments = _assign_archetypes(positions, edge_pairs, config, rng)
	else:
		# No archetypes → no clustering source. Leave every node unassigned;
		# the per-node loop skips content for a -1 assignment.
		type_assignments.resize(positions.size())
		type_assignments.fill(-1)

	# Pre-roll pass: GuaranteedPlacements decorate nodes with role tags.
	# starting_points were placed first into the position list (by index).
	await _emit_progress(progress_cb, 0.40, "Placing guarantees")
	var starter_indices := PackedInt32Array()
	for k in starters.size():
		starter_indices.append(k)
	var placement_ctx := _build_placement_context(
			positions, edge_pairs, type_assignments, starter_indices, config, rng)
	for placement in config.guaranteed_placements:
		if placement != null:
			placement.apply(placement_ctx)

	await _emit_progress(progress_cb, 0.45, "Rolling content")
	var nodes: Array[SkillNode] = []
	# Yield ~10 times across the per-node loop so the bar moves smoothly
	# without paying a frame per node. With 500 nodes that's every ~50.
	var yield_every := maxi(1, positions.size() / 10)
	for i in positions.size():
		var sn: SkillNode = _SKILL_NODE_SCENE.instantiate()
		sn.position = positions[i]
		sn.radius = config.node_radius
		var archetype_id: StringName = &""
		var archetype_color: Color = Color.WHITE
		var archetype_forbid: Array[StringName] = []
		var archetype_primary_stat: StringName = &""
		if type_assignments[i] >= 0:
			var policy: ArchetypePolicy = config.archetypes[type_assignments[i]]
			if policy != null:
				archetype_id = policy.id
				archetype_color = policy.color
				archetype_forbid = policy.forbid_tags
				archetype_primary_stat = policy.primary_stat
		if archetype_id != &"":
			var fp := {"archetype": archetype_id, "primary_stat": archetype_primary_stat}
			if not placement_ctx.role_tags[i].is_empty():
				fp["role_tags"] = placement_ctx.role_tags[i].duplicate()
			var role_tags: Array = placement_ctx.role_tags[i]
			var budget := 0
			if config.budget_policy != null:
				budget = config.budget_policy.compute_budget(
						archetype_id, positions[i], role_tags, rng)
			fp["budget"] = budget
			if config.modifier_pool_set != null:
				sn.modifiers = _roll_modifiers_v3(
						config.modifier_pool_set, config.weight_profiles,
						archetype_id, archetype_primary_stat, archetype_forbid,
						positions[i], i, budget, rng, fp)
			sn.set_meta("procgen_footprint", fp)
			# Border-channel stamp on BaseCircle (persistent type identity).
			# Owner colour stays free to drive the fill channel via SkillNode.
			sn.base_type_color = archetype_color
			sn.set_meta("base_type", archetype_id)
			if archetype_primary_stat != &"":
				sn.set_meta("primary_stat", archetype_primary_stat)
			# Persist role tags for downstream inspection / debug overlays.
			if not placement_ctx.role_tags[i].is_empty():
				sn.set_meta("role_tags", placement_ctx.role_tags[i].duplicate())
		graph.add_skill_node(sn)
		# After add_skill_node, so the node is in the tree and its addon anchor is
		# listening. Outside the archetype gate, so a keystone lands even on a node
		# procgen rolled no archetype for. The stamp overwrites the archetype colour
		# by design — a landmark outranks its terrain. Effects stay a live reference
		# on `sn.keystone`, granted by AllocationSystem on allocate.
		if placement_ctx.keystones[i] != null:
			placement_ctx.keystones[i].stamp(sn)
		_roll_and_attach_addons(sn, config, rng)
		nodes.append(sn)
		if i > 0 and i % yield_every == 0:
			# 0.45 → 0.92 over the per-node loop.
			var frac: float = 0.45 + 0.47 * (float(i) / float(positions.size()))
			await _emit_progress(progress_cb, frac, "Rolling content")

	await _emit_progress(progress_cb, 0.95, "Wiring edges")
	for pair in edge_pairs:
		graph.add_edge(nodes[pair.x], nodes[pair.y])
	
	# Add self-loops
	if config.self_loop_rate > 0.0:
		for node in nodes:
			if rng.randf() < config.self_loop_rate:
				graph.add_edge(node, node)

	# Starting points were seeded first into Poisson; they occupy positions[0..n).
	var starting_nodes: Array[SkillNode] = []
	for i in min(starters.size(), nodes.size()):
		starting_nodes.append(nodes[i])

	await _emit_progress(progress_cb, 1.0, "Done")
	return {"nodes": nodes, "starting_nodes": starting_nodes, "starters": starters}


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


# ── Random starter placement (issue #15) ──────────────────────────────────


## Appends up to [member GraphProcgenConfig.n_random_starters] fresh
## StartingPoints to `starters`, each rejection-sampled inside the shape
## mask and required to sit at least `viability_radius` from every prior
## starter. Bounded retries; warns if any anchor couldn't be placed so a
## level designer sees the squeeze instead of silently shipping fewer NPCs.
static func _place_random_starters(
		starters: Array[StartingPoint],
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> void:
	if config.n_random_starters <= 0 or config.shape_mask == null:
		return
	var bounds := config.shape_mask.aabb()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var min_sq := config.viability_radius * config.viability_radius
	for i in config.n_random_starters:
		var placed := false
		for _t in maxi(1, config.random_starter_max_tries):
			var p := Vector2(
					rng.randf_range(bounds.position.x, bounds.end.x),
					rng.randf_range(bounds.position.y, bounds.end.y))
			if not config.shape_mask.contains(p):
				continue
			var ok := true
			for sp in starters:
				if p.distance_squared_to(sp.position) < min_sq:
					ok = false
					break
			if not ok:
				continue
			var new_sp := StartingPoint.new()
			new_sp.position = p
			new_sp.id = StringName("%s_%d" % [config.random_starter_id_prefix, i])
			starters.append(new_sp)
			placed = true
			break
		if not placed:
			push_warning("GraphProcgen: couldn't place random starter %d after %d tries — viability_radius too large for shape/anchor density?" % [i, config.random_starter_max_tries])


# ── Topology ──────────────────────────────────────────────────────────────


## Returns edge pairs as [Vector2i(from_idx, to_idx)]. Always includes a
## spanning tree (graph stays connected); fills in shortest leftover Delaunay
## edges up to `connectivity` fraction.
static func _triangulate_and_prune(positions: Array[Vector2], connectivity: float) -> Array[Vector2i]:
	var pts := PackedVector2Array(positions)
	var tris: PackedInt32Array = Geometry2D.triangulate_delaunay(pts)
	# Dedup unordered edge pairs; key = lo * N + hi.
	var n := positions.size()
	var seen := {}
	var edges: Array[Vector2i] = []
	var lengths: Array[float] = []
	var t := 0
	while t < tris.size():
		var a := tris[t]; var b := tris[t + 1]; var c := tris[t + 2]
		for pair in [Vector2i(a, b), Vector2i(b, c), Vector2i(a, c)]:
			var lo := mini(pair.x, pair.y)
			var hi := maxi(pair.x, pair.y)
			var key := lo * n + hi
			if seen.has(key):
				continue
			seen[key] = true
			var v := Vector2i(lo, hi)
			edges.append(v)
			lengths.append(positions[lo].distance_squared_to(positions[hi]))
		t += 3

	# Sort indices by length asc — Kruskal needs shortest first; later we also
	# pick shortest leftovers, so one sort serves both passes.
	var order := range(edges.size())
	order.sort_custom(func(i, j): return lengths[i] < lengths[j])

	var parent := range(n)
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x

	var kept: Array[Vector2i] = []
	var extras: Array[Vector2i] = []
	for idx in order:
		var e: Vector2i = edges[idx]
		var ra: int = find.call(e.x)
		var rb: int = find.call(e.y)
		if ra != rb:
			parent[ra] = rb
			kept.append(e)
		else:
			extras.append(e)

	var extra_target := int(round(connectivity * extras.size()))
	for i in extra_target:
		kept.append(extras[i])
	return kept


# ── Clustering: target-driven BFS-grow ───────────────────────────────────


## Cluster assignment. Returns an int per position, indexing into
## [GraphProcgenConfig.archetypes]. Algorithm (BFS-grow; see the clustering
## section of docs/domain/procgen-v2.md):
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
	if n == 0 or config.archetypes.is_empty():
		return out

	# Step 1: target counts per archetype (normalised target_ratio).
	var total_ratio := 0.0
	for a in config.archetypes:
		if a != null:
			total_ratio += maxf(0.0, a.target_ratio)
	if total_ratio <= 0.0:
		# All-zero: uniform fallback.
		for k in config.archetypes.size():
			if config.archetypes[k] != null:
				total_ratio += 1.0
	var target_counts: Array[int] = []
	target_counts.resize(config.archetypes.size())
	var assigned_so_far := 0
	for k in config.archetypes.size():
		var policy: ArchetypePolicy = config.archetypes[k]
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
	for k in config.archetypes.size():
		var policy: ArchetypePolicy = config.archetypes[k]
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
	counts.resize(config.archetypes.size())
	var total_assigned := 0
	for i in n:
		if out[i] != -1 and out[i] < counts.size():
			counts[out[i]] += 1
			total_assigned += 1
	var balancer: ArchetypeBalancer = config.archetype_balancer
	var use_balancer := balancer != null and balancer.enabled
	for i in n:
		if out[i] != -1:
			continue
		var found := _bfs_to_first_claimed(i, out, adj)
		if found != -1:
			out[i] = found
		else:
			# Disconnected & nothing claimed reachable.
			out[i] = (balancer.pick(config.archetypes, counts, total_assigned, rng)
					if use_balancer else _pick_archetype_by_ratio(config.archetypes, rng))
		if out[i] >= 0 and out[i] < counts.size():
			counts[out[i]] += 1
			total_assigned += 1

	# Step 7: cluster_jitter reroll per archetype.
	for i in n:
		var policy: ArchetypePolicy = config.archetypes[out[i]] if out[i] >= 0 and out[i] < config.archetypes.size() else null
		if policy != null and rng.randf() < policy.cluster_jitter:
			var prev := out[i]
			out[i] = (balancer.pick(config.archetypes, counts, total_assigned, rng)
					if use_balancer else _pick_archetype_by_ratio(config.archetypes, rng))
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
	# Per-node empty role-tag arrays + null keystone slots.
	var rt: Array = []
	rt.resize(positions.size())
	for i in positions.size():
		rt[i] = [] as Array[StringName]
	ctx.role_tags = rt
	var ks: Array = []
	ks.resize(positions.size())
	ctx.keystones = ks
	return ctx


# ── Addon roll (second pass) ─────────────────────────────────────────────


static func _roll_and_attach_addons(
		sn: SkillNode,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> void:
	var policy: AddonPolicy = config.addon_policy
	if policy == null or policy.pool == null:
		return
	var slots := policy.sample_slot_count(rng)
	if slots <= 0:
		return
	var anchor := sn.get_node_or_null("Visuals/AddonAnchor") as Node
	if anchor == null:
		return
	# Track unique-addon scenes already minted on this node so we filter
	# duplicates out of subsequent slot picks. The scene PackedScene IS the
	# uniqueness key — same scene → same uniqueness class.
	var minted_unique_scenes: Array = []
	for _i in slots:
		var entry := _weighted_pick_addon(policy.pool, minted_unique_scenes, rng)
		if entry == null:
			break
		var instance: SkillNodeAddon = entry.mint(rng)
		if instance == null:
			break
		anchor.add_child(instance)
		if instance.unique:
			minted_unique_scenes.append(entry.addon_scene)


static func _weighted_pick_addon(
		pool: AddonPool,
		minted_unique_scenes: Array,
		rng: RandomNumberGenerator,
) -> AddonPoolEntry:
	var total := 0.0
	for e in pool.entries:
		if e == null or e.weight <= 0.0 or e.addon_scene == null:
			continue
		if e.addon_scene in minted_unique_scenes:
			continue
		total += e.weight
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for e in pool.entries:
		if e == null or e.weight <= 0.0 or e.addon_scene == null:
			continue
		if e.addon_scene in minted_unique_scenes:
			continue
		r -= e.weight
		if r <= 0.0:
			return e
	return null


# ── Modifier roll ─────────────────────────────────────────────────────────


static func _has_forbidden_tag(entry: ModifierPoolEntry, forbid: Array[StringName]) -> bool:
	for t in entry.tags:
		if t in forbid:
			return true
	return false


## v3 phased modifier draw. Replaces the flat budget-exhaustion loop with a
## slot-count-then-budget model:
##   1. Roll total slot count, split into primary_share / off_share.
##   2. Phase 2: fill primary slots from PRIMARY pools matching primary_stat;
##      track peak_primary_cost.
##   3. Phase 3: fill off slots from off-attribute PRIMARY (cost-capped),
##      DEFENSIVE, and RARE pools (defensive/rare uncapped).
##
## See docs/domain/procgen-v3.md for design rationale.
static func _roll_modifiers_v3(
		pool_set: ModifierPoolSet,
		profiles: Array[Resource],
		archetype: StringName,
		primary_stat: StringName,
		forbid_tags: Array[StringName],
		position: Vector2,
		node_index: int,
		budget: int,
		rng: RandomNumberGenerator,
		fp: Dictionary = {},
) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	fp["phase"] = "v3"
	if pool_set == null or pool_set.packs.is_empty() or budget <= 0:
		return out
	var slots := pool_set.sample_slot_count(rng)
	var primary_share := int(ceil(float(slots) * pool_set.primary_share_ratio))
	primary_share = clampi(primary_share, 0, slots)
	var off_share := slots - primary_share
	fp["slots"] = slots
	fp["primary_slots"] = primary_share
	fp["off_slots"] = off_share

	var ctx := WeightContext.new()
	ctx.archetype = archetype
	ctx.position = position
	ctx.node_index = node_index
	ctx.already_rolled = out
	ctx.forbid_tags = forbid_tags

	var remaining := budget
	var peak_primary_cost := 0

	# Phase 2: primary slots.
	if primary_share > 0 and primary_stat != &"":
		var primary_entries := pool_set.flatten_for_phase(&"primary", primary_stat)
		for _i in primary_share:
			var entry := _weighted_pick_from(primary_entries, profiles, ctx, remaining, rng)
			if entry == null:
				break
			out.append(entry.roll(rng))
			remaining -= entry.cost
			peak_primary_cost = maxi(peak_primary_cost, entry.cost)
			if remaining <= 0:
				break

	# Phase 3: off-attribute + defensive + rare slots.
	if off_share > 0 and remaining > 0:
		var off_entries := pool_set.flatten_for_phase(&"off", primary_stat)
		var defensive_entries := pool_set.flatten_for_phase(&"defensive", primary_stat)
		var rare_entries := pool_set.flatten_for_phase(&"rare", primary_stat)
		# Cost-cap off-attribute entries relative to peak primary cost. Defensive
		# and rare are exempt (see ModifierPoolSet docstring).
		# Cap formula: floor(peak * factor) - offset.
		fp["peak_primary_cost"] = peak_primary_cost
		var cap := int(floor(float(peak_primary_cost) * pool_set.off_cost_cap_factor)) - pool_set.off_cost_cap_offset
		fp["off_cap"] = cap
		var off_capped: Array[ModifierPoolEntry] = []
		if peak_primary_cost > 0:
			for e in off_entries:
				if e != null and e.cost <= cap:
					off_capped.append(e)
		else:
			# No primary picks happened (no primary_stat, or empty primary pools).
			# Don't cap — off-attribute is the only stat content available.
			off_capped = off_entries
		var combined: Array[ModifierPoolEntry] = []
		combined.append_array(off_capped)
		combined.append_array(defensive_entries)
		combined.append_array(rare_entries)
		for _i in off_share:
			var entry := _weighted_pick_from(combined, profiles, ctx, remaining, rng)
			if entry == null:
				break
			out.append(entry.roll(rng))
			remaining -= entry.cost
			if remaining <= 0:
				break
	return out


## Picks one entry from a pre-filtered list, applying weight profiles. Shared
## by phase 2 and phase 3 of the v3 draw.
static func _weighted_pick_from(
		entries: Array[ModifierPoolEntry],
		profiles: Array[Resource],
		context: WeightContext,
		budget: int,
		rng: RandomNumberGenerator,
) -> ModifierPoolEntry:
	var affordable: Array[ModifierPoolEntry] = []
	var weights: Array[float] = []
	var total := 0.0
	for e in entries:
		if e == null or e.cost > budget or e.weight <= 0.0:
			continue
		if not context.forbid_tags.is_empty() and _has_forbidden_tag(e, context.forbid_tags):
			continue
		var w := e.weight
		for p in profiles:
			if p == null:
				continue
			w *= p.multiplier_for(e, context)
			if w <= 0.0:
				break
		if w <= 0.0:
			continue
		affordable.append(e)
		weights.append(w)
		total += w
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for i in affordable.size():
		r -= weights[i]
		if r <= 0.0:
			return affordable[i]
	return affordable.back()


## Fills `outer_radius` on radial fields/profiles that opted in (set to 0 or
## negative) from the active shape mask's resolved outer extent. Lets a
## RadialGradientField/RadialBandProfile track an auto-scaled mask without
## the designer hard-coding the size in two places.
static func _propagate_mask_radius(config: GraphProcgenConfig) -> void:
	if config.shape_mask == null:
		return
	var aabb := config.shape_mask.aabb()
	var resolved_radius := 0.5 * minf(aabb.size.x, aabb.size.y)
	if resolved_radius <= 0.0:
		return
	# Budget field
	if config.budget_policy != null:
		var bf := config.budget_policy.budget_field
		if bf is RadialGradientField and (bf as RadialGradientField).outer_radius <= 0.0:
			(bf as RadialGradientField).outer_radius = resolved_radius
	# RadialBandProfile (any in the weight pipeline)
	for p in config.weight_profiles:
		if p is RadialBandProfile and (p as RadialBandProfile).outer_radius <= 0.0:
			(p as RadialBandProfile).outer_radius = resolved_radius
