@tool
class_name HopRangeFinder
extends RangeFinder

## Shortest-path edge count via the live graph (through the global
## [Navigator]'s AStar mirror — owned-by-anyone, not just attacker).

@export var max_hops: int = 3


func in_range(attacker: Entity, source: SkillNode, candidate: SkillNode) -> bool:
	if source == null or candidate == null:
		return false
	if attacker == null or attacker.navigator == null:
		return false
	var graph := attacker.navigator.graph
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
	return path.size() - 1 <= _effective_max_hops(attacker, source)


## Round-to-nearest scaling so a single +20% from INT pushes a 3-hop spell
## to 4 hops (3 × 1.2 ≈ 3.6 → 4) rather than getting eaten by truncation.
func _effective_max_hops(attacker: Entity, source: SkillNode) -> int:
	return int(round(float(max_hops) * spell_range_multiplier(attacker, source)))


## One BFS over [param mirror], not one AStar query per candidate. Pass the
## entity's own [EntityNavigator] to measure hops through owned territory only.
##
## Reach stays unscaled (raw `max_hops`, no `spell_range`) whenever
## [param attacker] is `null` — auras don't inherit a caster stat, and that's
## also every pre-#385 caller, so the default keeps them bit-for-bit unchanged.
## A non-null attacker (only [MagicAttackPlan]'s highlight cache passes one)
## reads [method _effective_max_hops] instead, matching what [method in_range]
## would have computed per candidate.
func gather(source: SkillNode, mirror: GraphMirror, attacker: Entity = null) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	var hops := max_hops if attacker == null else _effective_max_hops(attacker, source)
	var depths: Dictionary[SkillNode, int] = mirror.nodes_within(source, hops)
	for node in depths:
		out[node] = float(depths[node])
	return out


func max_reach() -> float:
	return float(max_hops)


func get_visual(attacker: Entity, source: SkillNode) -> RangeVisual:
	var visual := RangeVisual.new()
	var hops := _effective_max_hops(attacker, source)
	if source == null or hops <= 0:
		return visual
	if attacker == null or attacker.navigator == null:
		return visual
	var graph := attacker.navigator.graph
	if graph == null:
		return visual
	var nav := graph.navigator
	if nav == null:
		return visual
	# Hop distances from source, capped at hops, via the shared mirror BFS.
	var depths := nav.nodes_within(source, hops)  # {SkillNode: hops}
	if depths.is_empty():
		return visual
	# Walk live edges; an edge is lit when traversing it from the nearer endpoint
	# stays within hops. hops_remaining = budget left after that step.
	for edge in graph.get_edges():
		if edge == null or edge.from == null or edge.to == null:
			continue
		var has_a: bool = depths.has(edge.from)
		var has_b: bool = depths.has(edge.to)
		if not (has_a or has_b):
			continue
		var d_min: int = hops
		if has_a:
			d_min = depths[edge.from]
		if has_b:
			d_min = min(d_min, int(depths[edge.to]))
		var depth_of_edge := d_min + 1
		if depth_of_edge > hops:
			continue
		var hops_remaining := hops - depth_of_edge
		visual.edges.append(RangeVisual.EdgeEntry.new(edge, hops_remaining, hops))
	return visual
