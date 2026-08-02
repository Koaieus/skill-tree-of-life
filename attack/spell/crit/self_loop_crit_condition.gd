@tool
class_name SelfLoopCritCondition
extends CritCondition

## Crits when the spell traversed a self-loop edge to land here — i.e. the
## branch's predecessor IS its current node. A self-loop edge node-fans two
## copies back at itself; the resolver stamps `predecessor = current_node` on
## those hops, so the predicate is [code]state.predecessor == target[/code] —
## not [code]target.self_loop_count > 0[/code] (the previous broken form,
## which crited any landing on a self-loop-bearing node, including the first
## hit and edge hops into it). See #353.
##
## First hit doesn't crit: at the seed, [member CastSpell.predecessor] is
## null, so [code]null == target[/code] is false. An edge hop into a node
## with a self-loop also doesn't crit: predecessor is the upstream node, not
## the target.

func evaluate(state: CastSpell, target: SkillNode, _outcome: AttackOutcome) -> bool:
	if state == null or target == null:
		return false
	return state.predecessor == target