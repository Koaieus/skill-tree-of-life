@tool
class_name NodeTargeting
extends Targeting

## Any single node whose ownership matches [member Targeting.ownership_filter],
## within the optional [member Targeting.range_finder]'s reach of the source. If
## `range_finder` is null, reach is unlimited. Both live on [Targeting].
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


func is_valid_target(plan: AttackPlan, source: SkillNode, candidate: SkillNode) -> bool:
	if candidate == null or source == null or plan == null or plan.attacker == null:
		return false
	if candidate.ownership_bit(plan.attacker) & ownership_filter == 0:
		return false
	if range_finder != null and not range_finder.in_range(plan.attacker, source, candidate):
		return false
	return true


## Player-facing "who this can hit" line for [SpellTooltip]'s Cast section
## (#764), worded through the shared ownership-bit vocabulary (#384) — the
## SAME ONE [OwnerFilter] speaks, kept independent here since that class
## lives under `attack/spell/propagation/`, owned by other in-flight work.
##
## [b]Any (15) reads as "any node," never falls through to a bare "node."[/b]
## That fall-through was the bug LAN-08 surfaced on Healing Beam, which
## authors Any on purpose (heals either side) — see this file's top docstring.
func get_description() -> String:
	const ALL_BITS := (
		SkillNode.Ownership.NEUTRAL | SkillNode.Ownership.MINE
		| SkillNode.Ownership.ALLY | SkillNode.Ownership.HOSTILE
	)
	if (ownership_filter & ALL_BITS) == ALL_BITS:
		return "Hits any node."
	var parts: PackedStringArray = []
	if ownership_filter & SkillNode.Ownership.MINE:
		parts.append("own")
	if ownership_filter & SkillNode.Ownership.ALLY:
		parts.append("ally")
	if ownership_filter & SkillNode.Ownership.HOSTILE:
		parts.append("enemy-occupied")
	if ownership_filter & SkillNode.Ownership.NEUTRAL:
		parts.append("unallocated")
	if parts.is_empty():
		return "Hits nothing."
	return "Hits %s nodes." % " or ".join(parts)
