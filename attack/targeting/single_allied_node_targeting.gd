class_name SingleAlliedNodeTargeting
extends Targeting

## A node owned by the attacker, within [member max_range] scene-pixels of
## the source node. For buffs / heals.

@export var max_range: float = 200.0


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	if candidate.owned_by != plan.attacker:
		return false
	return source.global_position.distance_to(candidate.global_position) <= max_range
