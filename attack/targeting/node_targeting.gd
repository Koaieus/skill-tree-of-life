@tool
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
##
## [OwnerFilter] (spell propagation) takes the SAME flag set: who a spell may
## be aimed at and who it may chain into are one vocabulary. Keep them in step.
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


## ONE gather sweep, not one per-pair query per board node (#942). The base
## default runs [method is_valid_target] over every node, and for a hop finder
## each of those is a full AStar — 2k nodes, 2k path searches, to paint one
## highlight. [method RangeFinder.gather] answers the same question in one
## bounded BFS (hops) or one scan (euclid); the ownership filter is then
## applied over that reach map, the same gather-then-filter shape as
## [SpellTargetUnion]. [method is_valid_target] stays the per-pair truth for a
## single candidate and this MUST agree with it as a set — pinned by
## test_targeting.gd's equivalence tests — which holds because the sweep reads
## the same whole-board `graph.navigator` mirror `in_range` does, with the
## attacker passed so `effective_*` reach scaling folds in identically.
##
## No finder means unlimited reach, so there is nothing to sweep: the base
## per-node filter is the right (and cheap) path then.
func valid_targets(plan: AttackPlan, source: SkillNode) -> Array[SkillNode]:
	if range_finder == null:
		return _filter_skill_nodes(plan, source)
	var result: Array[SkillNode] = []
	if source == null or plan == null or plan.attacker == null or plan.attacker.navigator == null:
		return result
	var graph := plan.attacker.navigator.graph
	if graph == null or graph.navigator == null:
		return result
	var reach: Dictionary[SkillNode, float] = range_finder.gather(source, graph.navigator, plan.attacker)
	for candidate: SkillNode in reach:
		if candidate.ownership_bit(plan.attacker) & ownership_filter != 0:
			result.append(candidate)
	return result


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


## The authored [member range_finder] — null means unlimited reach, exactly as
## [method is_valid_target] reads it. See [method Targeting.get_range_finder].
func get_range_finder() -> RangeFinder:
	return range_finder
