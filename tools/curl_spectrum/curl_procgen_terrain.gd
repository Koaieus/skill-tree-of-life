class_name CurlProcgenTerrain
extends RefCounted

## Real playable ground, as a [CurlTerrain] (#705).
##
## Stages 1–3 of the shipped pipeline and nothing else: Poisson-disk sample
## inside the mask, Delaunay, prune to the MST plus a `connectivity` share of
## the shortest leftovers. Those are the exact calls
## [method GraphProcgen.generate] makes — [method PoissonDiskSampler.sample] and
## `GraphProcgen._triangulate_and_prune` — never a re-implementation, because
## the prune's shortest-extras-first rule is precisely the thing under
## measurement. Stages 4–6 (archetypes, modifier draws, node instantiation)
## decide what a node IS and cannot move an edge, so they are skipped and a
## sweep costs milliseconds per map instead of seconds.
##
## [b]Self-loops are deliberately absent.[/b] Procgen adds them (a tiered draw,
## `topology.self_loop_*`) and Cyclone refuses every one — [NoSelfLoopFilter],
## and [method Curl.rank_indices] has no angular slot for a zero-length edge
## anyway. A self-loop cannot change a curl, so leaving it out of the operator
## changes no number here.

const _SHAPE_MASK := preload("res://procgen/placement/circular_shape_mask.gd")


## `node_count` points at the shipped spacing, pruned at `connectivity`.
##
## [param node_radius] / [param node_padding] default to the values both
## shipped topology modules author (`procgen/modules/*/topology.tres`); the
## whole pipeline is expressed in units of `min_dist`, so they only zoom the
## board and never change a ranking.
static func sample(
		seed_value: int,
		node_count: int,
		connectivity: float,
		node_radius: float = 32.0,
		node_padding: float = 86.0) -> CurlTerrain:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var min_dist := 2.0 * node_radius + node_padding
	var mask = _SHAPE_MASK.new()
	mask.size_for(GraphProcgen.target_area_for_node_count(node_count, min_dist), min_dist * 4.0)
	var anchors: Array[Vector2] = []
	var positions := PoissonDiskSampler.sample(mask, min_dist, node_count, anchors, rng)
	var pairs := GraphProcgen._triangulate_and_prune(positions, connectivity)
	var pts := PackedVector2Array(positions)
	var edges: Array = []
	for pair in pairs:
		edges.append([pair.x, pair.y])
	return CurlTerrain.from_edges(
			"procgen-n%d-c%.2f-s%d" % [node_count, connectivity, seed_value], pts, edges)


## Indices worth casting AT: Cyclone's `min_degree = 4` gate means a node of
## graph degree below 4 cannot be targeted at all, so a sweep that averages over
## every node is averaging over ground no cast can reach. Sorted by index, so a
## caller picking `count` of them evenly spaced gets a fixed, seed-reproducible
## sample.
static func castable_targets(terrain: CurlTerrain, min_degree: int = 4) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in terrain.positions.size():
		if terrain.degree(i) >= min_degree:
			out.append(i)
	return out
