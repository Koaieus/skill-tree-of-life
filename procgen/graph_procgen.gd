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
	var type_assignments := _assign_types(positions, config, rng)

	var nodes: Array[SkillNode] = []
	for i in positions.size():
		var sn: SkillNode = _SKILL_NODE_SCENE.instantiate()
		sn.position = positions[i]
		sn.radius = config.node_radius
		var type_def: NodeTypeDef = config.node_types[type_assignments[i]] if not config.node_types.is_empty() else null
		if type_def != null:
			var field_scale := 1.0 if config.budget_field == null else config.budget_field.sample(positions[i])
			sn.modifiers = _roll_modifiers(type_def, field_scale, rng)
			# Border-channel stamp on BaseCircle (persistent type identity).
			# Owner colour stays free to drive the fill channel via SkillNode.
			sn.base_type_color = type_def.color
			sn.set_meta("base_type", type_def.id)
		graph.add_skill_node(sn)
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


# ── Modifier roll ─────────────────────────────────────────────────────────


static func _roll_modifiers(type_def: NodeTypeDef, budget_scale: float, rng: RandomNumberGenerator) -> Array[StatModifierDef]:
	if type_def.modifier_pool == null:
		return []
	var raw := rng.randi_range(type_def.budget_min, type_def.budget_max)
	var budget := maxi(0, int(round(raw * budget_scale)))
	return type_def.modifier_pool.roll(budget, rng)
