class_name NodeTargeting
extends Targeting

## Any single node whose ownership matches [member ownership_filter], within the
## optional [member range_finder]'s reach of the source. If `range_finder` is
## null, reach is unlimited.
##
## [b]Who a spell can reach is orthogonal to what it does to them.[/b] The filter
## does not imply the effect's sign: a damage spell may be authored Friendly or
## Any (friendly fire), and a heal may be authored Hostile or Any (healing the
## opponent). Both are deliberate design space, not mistakes to be linted out —
## [code]healing_beam.tres[/code] is Any *on purpose*, so mind your enemies.
## Hostile is merely the common case, hence the default.
##
## For "owned by the attacker" as a hard constraint, use [member ownership_filter]
## `= Mine` (2).


## Four mutually exclusive buckets (#384, see [method SkillNode.ownership_bit]):
## Neutral 1 / Mine 2 / Ally 4 / Hostile 8. `Friendly`/`Allocated`/`Any` are
## composites, not extra bits — they let the inspector's flag checkboxes reach
## a common OR-of-bits directly instead of hand-combining Mine+Ally each time.
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15") var ownership_filter: int = 8
@export var range_finder: RangeFinder


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	if candidate.ownership_bit(plan.attacker) & ownership_filter == 0:
		return false
	if range_finder != null and not range_finder.in_range(plan.attacker, source, candidate):
		return false
	return true
