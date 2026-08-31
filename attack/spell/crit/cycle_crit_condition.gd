@tool
class_name CycleCritCondition
extends CritCondition

## Crits when this landing CLOSED a cycle — the front stepped onto a node its
## own lineage had already struck, completing a loop through the graph.
##
## Reads [member CastSpell.closed_cycle], which [CycloneStep] stamps at mint
## and [CycloneReducer] ORs across converging fronts. This is the same Design A
## split [ConvergenceCritCondition] documents: the step/reducer does the math
## and stamps the fact, the condition owns the policy and stays a read-only
## predicate over the landed state.
##
## [b]It cannot re-derive the fact[/b], which is why the flag exists. A closing
## mint truncates [member CastSpell.visited] to the ring it just walked, and
## the landed node is the last entry of that ring — so
## `state.visited.has(state.current_node)` is true on every landing, closing or
## not. The trail at landing time no longer remembers which it was.
##
## One of Cyclone's two crit conditions (#696, #699), and the ODD half of the
## pair: this fires where a single lineage laps home onto its own trail, which
## is the only way an odd ring can be closed, since its two arms differ by one
## and pass mid-edge instead of meeting. [ConvergenceCritCondition] covers the
## even half, where the arms are equal and merge head-on at hop L/2.

func evaluate(state: CastSpell, _target: SkillNode, _outcome: AttackOutcome) -> bool:
	if state == null:
		return false
	return state.closed_cycle
