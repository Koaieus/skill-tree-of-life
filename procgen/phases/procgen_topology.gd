@tool
class_name ProcgenTopology
extends RefCounted

## Stages 1–3 of [method GraphProcgen.generate] (hub #422, child 2),
## extracted from `graph_procgen.gd` with their bodies unchanged: config
## resolve (mask auto-scale + radius propagation), starter assembly,
## Poisson-disk sampling and the Delaunay → MST + extras prune. Static and
## stateless — the caller owns the RNG and hands it in (starter `plan` and
## Poisson draw from it in the same order as before), and this phase never
## touches the progress callback. Same seed → byte-identical graph is
## guarded by `test/integration/procgen/test_procgen_golden.gd`.


## What [method run] hands back. `ok == false` means generation cannot
## continue (roster cannot seat, or the sampler produced no points); the
## error was already pushed, `starters` is still filled so the caller can
## return it, and `positions` / `edge_pairs` are empty.
class Result extends RefCounted:
	var ok: bool = true
	var starters: Array[StartingPoint] = []
	var anchors: Array[Vector2] = []
	var positions: Array[Vector2] = []
	var edge_pairs: Array[Vector2i] = []


## Starters → anchors → Poisson positions → pruned edge pairs, on an
## already-resolved `config` (see [method resolve_config]).
static func run(config: GraphProcgenConfig, rng: RandomNumberGenerator) -> Result:
	var out := Result.new()
	var min_dist := _min_node_dist(config.topology)
	# Final ordered starter list = manual entries first, then any random anchors
	# we place. Caller reads back via `starting_nodes` in the same order, so
	# manual vs. random can be told apart by index.
	var starters: Array[StartingPoint] = []
	if config.starting.starter_placement != null:
		# Camp-relative annulus placement replaces the whole manual
		# list. Read the resolved radius the same way _propagate_mask_radius
		# does — the mask is already auto-scaled by this point.
		var resolved_radius := 0.0
		if config.shape.shape_mask != null:
			var mask_aabb := config.shape.shape_mask.aabb()
			resolved_radius = 0.5 * minf(mask_aabb.size.x, mask_aabb.size.y)
		starters = config.starting.starter_placement.plan(
				config.camp_sizes, resolved_radius, min_dist, rng,
				config.shape.shape_mask, config.starting.random_starter_max_tries)
		# Consumers zip starters onto participants by index, so a short plan
		# (a placement skips a contender it cannot seat) would hand a later
		# participant a neighbour's spawn. Refuse rather than mis-zip.
		var wanted := 0
		for size in config.camp_sizes:
			wanted += size
		if starters.size() != wanted:
			push_error("GraphProcgen: roster cannot seat — placement returned %d starters for %d participants"
					% [starters.size(), wanted])
			out.starters = starters
			out.ok = false
			return out
	else:
		for sp in config.starting.starting_points:
			if sp != null:
				starters.append(sp)
	out.starters = starters

	var anchors: Array[Vector2] = []
	for sp in starters:
		anchors.append(sp.position)
	out.anchors = anchors
	var positions := PoissonDiskSampler.sample(
			config.shape.shape_mask, min_dist, config.topology.node_count,
			anchors, rng)
	if positions.is_empty():
		push_warning("GraphProcgen: sampler produced no points")
		out.ok = false
		return out
	out.positions = positions
	out.edge_pairs = triangulate_and_prune(positions, config.topology.connectivity)
	return out


## Returns edge pairs as [Vector2i(from_idx, to_idx)]. Always includes a
## spanning tree (graph stays connected); fills in shortest leftover Delaunay
## edges up to `connectivity` fraction.
static func triangulate_and_prune(positions: Array[Vector2], connectivity: float) -> Array[Vector2i]:
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
	var merges := 0
	for idx in order:
		var e: Vector2i = edges[idx]
		var ra: int = find.call(e.x)
		var rb: int = find.call(e.y)
		if ra != rb:
			parent[ra] = rb
			kept.append(e)
			merges += 1
		else:
			extras.append(e)

	# Connectivity certificate. Kruskal over the Delaunay candidate set
	# spans every node by construction: n nodes, m successful merges, n - m
	# components — and a skill tree being ONE component is a hard requirement
	# resting on that implementation detail. A bad graft (e.g. the cluster
	# stitching, or a degenerate triangulation) islands a region and breaks
	# this. Debug-only, zero cost.
	assert(n - merges == 1,
			"GraphProcgen: Kruskal over Delaunay candidates left %d components for %d nodes — the skill tree must be one connected component"
			% [n - merges, n])

	var extra_target := int(round(connectivity * extras.size()))
	for i in extra_target:
		kept.append(extras[i])
	return kept


# ── Config resolve ────────────────────────────────────────────────────────


## Returns a copy of `config` with its generate-time values resolved — the
## shape mask auto-scaled to `node_count` (when the mask opts in and
## `scale_mask` is set) and the mask radius handed to every [ScalarField].
## Never writes to `config`. The shallow duplicate shares the untouched
## modules by reference; the two it mutates — `shape` and `content` — are
## deep-copied, because both are module `.tres` files whose `duplicate(true)`
## stops at every ExtResource boundary (see test_procgen_carve_shape.gd): a
## write through the caller's reference would land on the cached on-disk
## module every other load of the preset shares.
## `scale_mask = false` keeps the authored mask size — a preview that samples
## the authored config rather than a generated map.
static func resolve_config(config: GraphProcgenConfig, scale_mask: bool = true) -> GraphProcgenConfig:
	var out: GraphProcgenConfig = config.duplicate()
	if out.shape != null:
		out.shape = out.shape.duplicate(true)
	if out.content != null:
		out.content = out.content.duplicate(true)
	if out.shape == null or out.shape.shape_mask == null:
		return out
	# Auto-size the shape mask so Poisson can fit node_count at the requested
	# spacing without under-filling. See GraphProcgen._POISSON_AREA_PER_POINT.
	if scale_mask and out.shape.shape_mask.auto_scale:
		var min_dist := _min_node_dist(out.topology)
		var target_area := GraphProcgen.target_area_for_node_count(out.topology.node_count, min_dist)
		out.shape.shape_mask.size_for(target_area, min_dist * 4.0)
	_propagate_mask_radius(out)
	return out


## Poisson spacing, sized for the LARGEST radius any node can carry:
## with a `node_radius_ramp` that is the ramp's asymptote, so a max-budget
## node still clears its neighbours; without one the uniform node_radius.
static func _min_node_dist(topology: GraphProcgenTopology) -> float:
	return 2.0 * topology.max_node_radius() + topology.node_padding


## Hands the active shape mask's resolved radius to every [ScalarField] the
## content holds. Which fields exist is each holder's answer
## ([method GraphProcgenContent.scalar_fields]); what a field does with the
## radius is its own ([method ScalarField.resolve_mask_radius]).
static func _propagate_mask_radius(config: GraphProcgenConfig) -> void:
	if config.shape.shape_mask == null or config.content == null:
		return
	var aabb := config.shape.shape_mask.aabb()
	var resolved_radius := 0.5 * minf(aabb.size.x, aabb.size.y)
	if resolved_radius <= 0.0:
		return
	for field in config.content.scalar_fields():
		field.resolve_mask_radius(resolved_radius)
