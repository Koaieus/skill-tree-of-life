@tool
class_name ConvergenceCritCondition
extends CritCondition

## Crits when ≥2 BFS wavefronts converged at this landing — i.e. two or more
## branches of the spell reached the same node in the same wave and were
## merged by the [IncidentReducer]. Reads [member CastSpell.incident_count],
## which is stamped by [SpellResolver] upstream of the crit roll, so the
## predicate fires on every code path (null reducer, Sum/Max/Min, cancel).
##
## The convergence crit is the identity of the Resonator spell (#352):
## diamonds, hexagons, and chained-diamond topologies crit on the
## reconverging node(s); straight lines and odd convergences don't.
##
## Design A (data coupling): the reducer does the math (Sum / Max / etc.) and
## stamps the fact ([code]incident_count[/code]); this condition owns the
## policy ([code]>= 2[/code]). Swappable for parity-rule or colour-rule
## variants (see #355 Chromatic Cascade) without touching the reducer.

func evaluate(state: CastSpell, _target: SkillNode, _outcome: AttackOutcome) -> bool:
	if state == null:
		return false
	return state.incident_count >= 2