class_name HopRangeFinder
extends RangeFinder

## Shortest-path edge count via the live graph (through the global
## [Navigator]'s AStar mirror — owned-by-anyone, not just attacker).

@export var max_hops: int = 3


func in_range(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if source == null or candidate == null:
		return false
	if plan == null or plan.attacker == null or plan.attacker.navigator == null:
		return false
	var graph := plan.attacker.navigator.graph
	if graph == null:
		return false
	var nav := graph.navigator
	if nav == null:
		return false
	var src_id := nav.vertex_id(source)
	var dst_id := nav.vertex_id(candidate)
	if src_id < 0 or dst_id < 0:
		return false
	var path := nav.astar.get_id_path(src_id, dst_id)
	if path.is_empty():
		return false
	return path.size() - 1 <= max_hops


func get_visual(plan: AttackPlan, source: SkillNode) -> RangeVisual:
	var visual := RangeVisual.new()
	if source == null or max_hops <= 0:
		return visual
	if plan == null or plan.attacker == null or plan.attacker.navigator == null:
		return visual
	var graph := plan.attacker.navigator.graph
	if graph == null:
		return visual
	var nav := graph.navigator
	if nav == null:
		return visual
	var src_id := nav.vertex_id(source)
	if src_id < 0:
		return visual
	# BFS distances from source, capped at max_hops, into a (point_id → depth) map.
	var depths: Dictionary[int, int] = {src_id: 0}
	var frontier: Array[int] = [src_id]
	while not frontier.is_empty():
		var next_frontier: Array[int] = []
		for cur in frontier:
			var d: int = depths[cur]
			if d >= max_hops:
				continue
			for nb in nav.astar.get_point_connections(cur):
				if depths.has(nb):
					continue
				depths[nb] = d + 1
				next_frontier.append(nb)
		frontier = next_frontier
	# Walk live edges; an edge is lit when traversing it from the nearer endpoint
	# stays within max_hops. hops_remaining = budget left after that step.
	for edge in graph.get_edges():
		if edge == null or edge.from == null or edge.to == null:
			continue
		var a_id := nav.vertex_id(edge.from)
		var b_id := nav.vertex_id(edge.to)
		if a_id < 0 or b_id < 0:
			continue
		var has_a: bool = depths.has(a_id)
		var has_b: bool = depths.has(b_id)
		if not (has_a or has_b):
			continue
		var d_min: int = max_hops
		if has_a:
			d_min = depths[a_id]
		if has_b:
			d_min = min(d_min, int(depths[b_id]))
		var depth_of_edge := d_min + 1
		if depth_of_edge > max_hops:
			continue
		var hops_remaining := max_hops - depth_of_edge
		visual.edges.append(RangeVisual.EdgeEntry.new(edge, hops_remaining, max_hops))
	return visual
