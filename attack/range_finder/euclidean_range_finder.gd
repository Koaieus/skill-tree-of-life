@tool
class_name EuclideanRangeFinder
extends RangeFinder

## Straight-line scene-pixel distance from source to candidate.

@export var max_distance: float = 250.0


func in_range(attacker: Entity, source: SkillNode, candidate: SkillNode) -> bool:
	if source == null or candidate == null:
		return false
	return source.global_position.distance_to(candidate.global_position) <= _effective_distance(attacker, source)


## One linear scan. Deliberately not a spatial index: an aura recompute runs on
## allocation events over a tens-of-nodes owned subgraph, not per frame over the
## whole graph (which is what earns VisionSystem its index). Reach stays
## unscaled whenever [param attacker] is `null` (every pre-#385 caller) — see
## [method RangeFinder.gather].
func gather(source: SkillNode, mirror: GraphMirror, attacker: Entity = null) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	var reach := max_distance if attacker == null else _effective_distance(attacker, source)
	for n in mirror.get_mirrored_nodes():
		var d := source.global_position.distance_to(n.global_position)
		if d <= reach:
			out[n] = d
	return out


func max_reach() -> float:
	return max_distance


func get_visual(attacker: Entity, source: SkillNode) -> RangeVisual:
	var visual := RangeVisual.new()
	if source == null:
		return visual
	var dist := _effective_distance(attacker, source)
	if dist <= 0.0:
		return visual
	visual.rings.append(RangeVisual.Ring.new(source.global_position, dist))
	return visual


func _effective_distance(attacker: Entity, source: SkillNode) -> float:
	return max_distance * spell_range_multiplier(attacker, source)
