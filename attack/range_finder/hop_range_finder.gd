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
	return path.size() - 1 <= _effective_max_hops(plan)


## Round-to-nearest scaling so a single +20% from INT pushes a 3-hop spell
## to 4 hops (3 × 1.2 ≈ 3.6 → 4) rather than getting eaten by truncation.
func _effective_max_hops(plan: AttackPlan) -> int:
	return int(round(float(max_hops) * spell_range_multiplier(plan)))


func get_visual(plan: AttackPlan, source: SkillNode) -> RangeVisual:
	var visual := RangeVisual.new()
	var max_hops := _effective_max_hops(plan)
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
	# Hop distances from source, capped at max_hops, via the shared mirror BFS.
	var depths := nav.nodes_within(source, max_hops)  # {SkillNode: hops}
	if depths.is_empty():
		return visual
	# Walk live edges; an edge is lit when traversing it from the nearer endpoint
	# stays within max_hops. hops_remaining = budget left after that step.
	for edge in graph.get_edges():
		if edge == null or edge.from == null or edge.to == null:
			continue
		var has_a: bool = depths.has(edge.from)
		var has_b: bool = depths.has(edge.to)
		if not (has_a or has_b):
			continue
		var d_min: int = max_hops
		if has_a:
			d_min = depths[edge.from]
		if has_b:
			d_min = min(d_min, int(depths[edge.to]))
		var depth_of_edge := d_min + 1
		if depth_of_edge > max_hops:
			continue
		var hops_remaining := max_hops - depth_of_edge
		visual.edges.append(RangeVisual.EdgeEntry.new(edge, hops_remaining, max_hops))
	return visual
