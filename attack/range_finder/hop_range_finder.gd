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
