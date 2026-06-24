class_name EuclideanRangeFinder
extends RangeFinder

## Straight-line scene-pixel distance from source to candidate.

@export var max_distance: float = 250.0


func in_range(_plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if source == null or candidate == null:
		return false
	return source.global_position.distance_to(candidate.global_position) <= max_distance


func get_visual(_plan: AttackPlan, source: SkillNode) -> RangeVisual:
	var visual := RangeVisual.new()
	if source == null or max_distance <= 0.0:
		return visual
	visual.rings.append(RangeVisual.Ring.new(source.global_position, max_distance))
	return visual
