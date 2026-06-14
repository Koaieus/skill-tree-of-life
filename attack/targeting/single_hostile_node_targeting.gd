class_name SingleHostileNodeTargeting
extends Targeting

## A node owned by any entity other than the attacker, within
## [member max_range] scene-pixels of the source node.

@export var max_range: float = 200.0


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	if candidate.owned_by == null or candidate.owned_by == plan.attacker:
		return false
	return source.global_position.distance_to(candidate.global_position) <= max_range
