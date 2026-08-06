class_name NodeTargeting
extends Targeting

## A node owned by the attacker, within the optional [member range_finder]'s
## reach of the source. For buffs / heals. If `range_finder` is null, any
## owned node is valid.


@export_flags("Neutral:1", "Friendly:2", "Hostile:4", "Allocated:6", "Any:7") var ownership_filter: int = 4
@export var range_finder: RangeFinder


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	var candidate_ownership_state: int = ( 
		# TODO: is this variable name correct? and check if this logic is sound or needs cleaning
		1 * int(not candidate.is_allocated)
		+ 2 * int(candidate.owned_by != null and candidate.owned_by == plan.attacker)
		+ 4 * int(candidate.owned_by != null and candidate.owned_by != plan.attacker)
	) 
	if candidate_ownership_state & ownership_filter == 0:
		return false
	if range_finder != null and not range_finder.in_range(plan.attacker, source, candidate):
		return false
	return true
