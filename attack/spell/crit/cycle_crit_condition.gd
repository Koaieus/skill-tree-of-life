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
## mint resets [member CastSpell.visited] to just the landed node, so
## `state.visited.has(state.current_node)` is true on every landing, closing or
## not — the trail at landing time no longer remembers.
##
## The identity of Cyclone (#696), and the odd-cycle counterpart to
## [ConvergenceCritCondition]: convergence crits where two equal-length branches
## meet head-on (even rings), this crits where one lineage laps home (odd rings).

func evaluate(state: CastSpell, _target: SkillNode, _outcome: AttackOutcome) -> bool:
	if state == null:
		return false
	return state.closed_cycle
