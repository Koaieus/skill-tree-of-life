class_name EuclideanRangeFinder
extends RangeFinder

## Straight-line scene-pixel distance from source to candidate.

@export var max_distance: float = 250.0


func in_range(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if source == null or candidate == null:
		return false
	return source.global_position.distance_to(candidate.global_position) <= _effective_distance(plan)


func get_visual(plan: AttackPlan, source: SkillNode) -> RangeVisual:
	var visual := RangeVisual.new()
	var dist := _effective_distance(plan)
	if source == null or dist <= 0.0:
		return visual
	visual.rings.append(RangeVisual.Ring.new(source.global_position, dist))
	return visual


func _effective_distance(plan: AttackPlan) -> float:
	return max_distance * spell_range_multiplier(plan)
