@tool
class_name GraphProcgen
extends RefCounted

## Pipeline runner. Static — no state beyond what flows through `generate`.
## Stages:
##   1. Poisson-disk sample positions inside the [ShapeMask] (with anchors).
##   2. Delaunay triangulate the points; that's our planar candidate edge set.
##   3. Prune to MST + a `connectivity`-controlled share of shortest extras.
##   4. Cluster-assign a [NodeTypeDef] per node (Voronoi seeds + jitter).
##   5. Per node, roll a budget and draw modifiers from the type's pool.
##   6. Instantiate SkillNodes + Edges under the [Graph].
##
## Returns a Dictionary `{nodes: Array[SkillNode], starting_nodes:
## Array[SkillNode]}` — `starting_nodes[i]` is the SkillNode that landed on
## `config.starting_points[i]`, for the caller to wire as entity cores.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


static func generate(config: GraphProcgenConfig, graph: Graph) -> Dictionary:
	assert(config != null, "GraphProcgen.generate: null config")
	assert(graph != null, "GraphProcgen.generate: null graph")
	assert(config.shape_mask != null, "GraphProcgen.generate: config.shape_mask is null")

	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed if config.seed != 0 else randi()

	var min_dist := 2.0 * config.node_radius + config.node_padding
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

	var edge_pairs := _triangulate_and_prune(positions, config.connectivity)
	var use_v2_clusters := config.use_archetype_policies and not config.archetypes.is_empty()
	var type_assignments: PackedInt32Array
	if use_v2_clusters:
		type_assignments = _assign_archetypes_v2(positions, edge_pairs, config, rng)
	else:
		type_assignments = _assign_types(positions, config, rng)

	# Pre-roll pass: GuaranteedPlacements decorate nodes with role tags.
	# starting_points were placed first into the position list (by index).
	var starter_indices := PackedInt32Array()
	for k in starters.size():
		starter_indices.append(k)
	var placement_ctx := _build_placement_context(
			positions, edge_pairs, type_assignments, starter_indices, config, rng)
	for placement in config.guaranteed_placements:
		if placement != null:
			placement.apply(placement_ctx)

	var nodes: Array[SkillNode] = []
	for i in positions.size():
		var sn: SkillNode = _SKILL_NODE_SCENE.instantiate()
		sn.position = positions[i]
		sn.radius = config.node_radius
		var archetype_id: StringName = &""
		var archetype_color: Color = Color.WHITE
		var type_def: NodeTypeDef = null
		if use_v2_clusters:
			var policy: ArchetypePolicy = config.archetypes[type_assignments[i]]
			if policy != null:
				archetype_id = policy.id
				archetype_color = policy.color
		elif not config.node_types.is_empty():
			type_def = config.node_types[type_assignments[i]]
			if type_def != null:
				archetype_id = type_def.id
				archetype_color = type_def.color
		if archetype_id != &"":
			var field_scale := 1.0 if config.budget_field == null else config.budget_field.sample(positions[i])
			if config.modifier_pool != null:
				var role_tags: Array = placement_ctx.role_tags[i]
				var budget := _compute_v2_budget(
						config.budget_policy, type_def, field_scale,
						archetype_id, positions[i], role_tags, rng)
				sn.modifiers = _roll_modifiers_v2(
						config.modifier_pool, config.weight_profiles,
						archetype_id, positions[i], i, budget, rng)
			elif type_def != null:
				sn.modifiers = _roll_modifiers(type_def, field_scale, rng)
			# Border-channel stamp on BaseCircle (persistent type identity).
			# Owner colour stays free to drive the fill channel via SkillNode.
			sn.base_type_color = archetype_color
			sn.set_meta("base_type", archetype_id)
			# Persist role tags for downstream inspection / debug overlays.
			if not placement_ctx.role_tags[i].is_empty():
				sn.set_meta("role_tags", placement_ctx.role_tags[i].duplicate())
			# Keystone reference (consumed by future allocation-hook wiring).
			if placement_ctx.keystones[i] != null:
				sn.set_meta("keystone", placement_ctx.keystones[i])
		graph.add_skill_node(sn)
		_roll_and_attach_addons(sn, config, rng)
		nodes.append(sn)

	for pair in edge_pairs:
		graph.add_edge(nodes[pair.x], nodes[pair.y])

	# Starting points were seeded first into Poisson; they occupy positions[0..n).
	var starting_nodes: Array[SkillNode] = []
	for i in min(starters.size(), nodes.size()):
		starting_nodes.append(nodes[i])

	return {"nodes": nodes, "starting_nodes": starting_nodes, "starters": starters}


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


# ── Clustering ────────────────────────────────────────────────────────────


## Returns an int per position, indexing into [member GraphProcgenConfig.node_types].
## Voronoi-style: `cluster_count` seed points each pick a weighted type; every
## node inherits its nearest seed's type. `cluster_jitter` rerolls per-node
## independently to soften cluster borders.
static func _assign_types(
		positions: Array[Vector2],
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(positions.size())
	if config.node_types.is_empty():
		return out

	# Build weight CDF once.
	var weights: Array[float] = []
	var total_weight := 0.0
	for t in config.node_types:
		var w := maxf(0.0, t.weight if t != null else 0.0)
		weights.append(w)
		total_weight += w
	if total_weight <= 0.0:
		# Degenerate: all zero — uniform fallback.
		for i in weights.size():
			weights[i] = 1.0
		total_weight = float(weights.size())

	var pick_type := func() -> int:
		var r := rng.randf() * total_weight
		for i in weights.size():
			r -= weights[i]
			if r <= 0.0:
				return i
		return weights.size() - 1

	# Seed clusters at random sampled positions.
	var seed_count := mini(maxi(1, config.cluster_count), positions.size())
	var seed_positions: Array[Vector2] = []
	var seed_types: Array[int] = []
	var used := {}
	while seed_positions.size() < seed_count:
		var pi := rng.randi() % positions.size()
		if used.has(pi):
			continue
		used[pi] = true
		seed_positions.append(positions[pi])
		seed_types.append(pick_type.call())

	for i in positions.size():
		if rng.randf() < config.cluster_jitter:
			out[i] = pick_type.call()
			continue
		var best := 0
		var best_sq := INF
		for s in seed_positions.size():
			var d := positions[i].distance_squared_to(seed_positions[s])
			if d < best_sq:
				best_sq = d
				best = s
		out[i] = seed_types[best]
	return out


# ── Clustering v2: target-driven BFS-grow ────────────────────────────────


## v2 cluster assignment. Returns an int per position, indexing into
## [GraphProcgenConfig.archetypes]. Algorithm (see docs/domain/procgen-v2.md):
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
static func _assign_archetypes_v2(
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


# ── Addon roll (procgen v2 second pass) ──────────────────────────────────


static func _roll_and_attach_addons(
		sn: SkillNode,
		config: GraphProcgenConfig,
		rng: RandomNumberGenerator,
) -> void:
	var policy: AddonPolicy = config.addon_policy
	if policy == null or policy.pool == null or policy.chance_per_node <= 0.0:
		return
	if rng.randf() >= policy.chance_per_node:
		return
	var budget := rng.randi_range(policy.addon_budget_min, policy.addon_budget_max)
	if budget <= 0:
		return
	var anchor := sn.get_node_or_null("Visuals/AddonAnchor") as Node
	if anchor == null:
		return
	var remaining := budget
	while true:
		var entry := _weighted_pick_addon(policy.pool, remaining, rng)
		if entry == null:
			break
		var instance := entry.mint(rng)
		if instance == null:
			break
		anchor.add_child(instance)
		remaining -= entry.cost
		if remaining <= 0:
			break


static func _weighted_pick_addon(
		pool: AddonPool,
		budget: int,
		rng: RandomNumberGenerator,
) -> AddonPoolEntry:
	var total := 0.0
	for e in pool.entries:
		if e != null and e.cost <= budget and e.weight > 0.0:
			total += e.weight
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for e in pool.entries:
		if e == null or e.cost > budget or e.weight <= 0.0:
			continue
		r -= e.weight
		if r <= 0.0:
			return e
	return null


# ── Modifier roll ─────────────────────────────────────────────────────────


static func _roll_modifiers(type_def: NodeTypeDef, budget_scale: float, rng: RandomNumberGenerator) -> Array[StatModifier]:
	if type_def.modifier_pool == null:
		return []
	var raw := rng.randi_range(type_def.budget_min, type_def.budget_max)
	var budget := maxi(0, int(round(raw * budget_scale)))
	return type_def.modifier_pool.roll(budget, rng)


# ── v2: universal pool + weight profile pipeline ─────────────────────────


## Budget for the v2 pass. If [BudgetPolicy] is set, it owns the formula
## (archetype × field × role). Otherwise falls back to v1's per-type
## budget_min/max + `config.budget_field` for compatibility.
static func _compute_v2_budget(
		policy: BudgetPolicy,
		type_def: NodeTypeDef,
		field_scale: float,
		archetype: StringName,
		position: Vector2,
		role_tags: Array,
		rng: RandomNumberGenerator,
) -> int:
	if policy != null:
		return policy.compute_budget(archetype, position, role_tags, rng)
	if type_def == null:
		return 0
	var raw := rng.randi_range(type_def.budget_min, type_def.budget_max)
	return maxi(0, int(round(raw * field_scale)))


## v2 modifier roll. Draws from a single universal pool with weight profiles
## composed multiplicatively. See docs/domain/procgen-v2.md.
static func _roll_modifiers_v2(
		pool: ModifierPool,
		profiles: Array[Resource],
		archetype: StringName,
		position: Vector2,
		node_index: int,
		budget: int,
		rng: RandomNumberGenerator,
) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if pool == null or pool.entries.is_empty() or budget <= 0:
		return out
	var ctx := WeightContext.new()
	ctx.archetype = archetype
	ctx.position = position
	ctx.node_index = node_index
	ctx.already_rolled = out  # alias — grows as we append
	var remaining := budget
	while true:
		var entry := _weighted_pick_v2(pool, profiles, ctx, remaining, rng)
		if entry == null:
			break
		out.append(entry.roll(rng))
		remaining -= entry.cost
		if remaining <= 0:
			break
	return out


static func _weighted_pick_v2(
		pool: ModifierPool,
		profiles: Array[Resource],
		context: WeightContext,
		budget: int,
		rng: RandomNumberGenerator,
) -> ModifierPoolEntry:
	var affordable: Array[ModifierPoolEntry] = []
	var weights: Array[float] = []
	var total := 0.0
	for e in pool.entries:
		if e == null or e.cost > budget or e.weight <= 0.0:
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
