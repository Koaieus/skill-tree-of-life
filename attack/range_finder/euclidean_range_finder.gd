class_name EuclideanRangeFinder
extends RangeFinder

## Straight-line scene-pixel distance from source to candidate.

@export var max_distance: float = 250.0


func in_range(attacker: Entity, source: SkillNode, candidate: SkillNode) -> bool:
	if source == null or candidate == null:
		return false
	return source.global_position.distance_to(candidate.global_position) <= _effective_distance(attacker)


func get_visual(attacker: Entity, source: SkillNode) -> RangeVisual:
	var visual := RangeVisual.new()
	var dist := _effective_distance(attacker)
	if source == null or dist <= 0.0:
		return visual
	visual.rings.append(RangeVisual.Ring.new(source.global_position, dist))
	return visual


func _effective_distance(attacker: Entity) -> float:
	return max_distance * spell_range_multiplier(attacker)
