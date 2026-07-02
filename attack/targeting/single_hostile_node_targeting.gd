class_name SingleHostileNodeTargeting
extends Targeting

## A node owned by any entity other than the attacker, within the optional
## [member range_finder]'s reach of the source node. If `range_finder` is
## null, ownership is the only check (any enemy node anywhere is valid).

@export var range_finder: RangeFinder


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	if candidate.owned_by == null or candidate.owned_by == plan.attacker:
		return false
	if range_finder != null and not range_finder.in_range(plan.attacker, source, candidate):
		return false
	return true
