class_name SingleAlliedNodeTargeting
extends Targeting

## A node owned by the attacker, within the optional [member range_finder]'s
## reach of the source. For buffs / heals. If `range_finder` is null, any
## owned node is valid.

@export var range_finder: RangeFinder


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	if candidate.owned_by != plan.attacker:
		return false
	if range_finder != null and not range_finder.in_range(plan, source, candidate):
		return false
	return true
