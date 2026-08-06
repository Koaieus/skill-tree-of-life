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
## For "owned by the attacker" as a hard constraint, see
## [SingleAlliedNodeTargeting].


@export_flags("Neutral:1", "Friendly:2", "Hostile:4", "Allocated:6", "Any:7") var ownership_filter: int = 4
@export var range_finder: RangeFinder


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	# Exactly one bit, matching the `ownership_filter` flag layout. The three
	# cases are mutually exclusive, so the sum is a single set bit — but keep
	# the arithmetic form: it reads as the flag table it mirrors.
	# (`&` binds tighter than `==` in GDScript, so the test below needs no parens.)
	var candidate_ownership_bit: int = (
		1 * int(not candidate.is_allocated)
		+ 2 * int(candidate.owned_by != null and candidate.owned_by == plan.attacker)
		+ 4 * int(candidate.owned_by != null and candidate.owned_by != plan.attacker)
	)
	if candidate_ownership_bit & ownership_filter == 0:
		return false
	if range_finder != null and not range_finder.in_range(plan.attacker, source, candidate):
		return false
	return true
