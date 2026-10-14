@tool
class_name SelfLoopCondition
extends LandingCondition

## Crits when ANY front merged into this landing traversed a self-loop edge
## to get here — i.e. [member CastSpell.arrived_from] contains the landed node.
## A self-loop edge node-fans a copy back at itself, so that front's
## predecessor IS the node. [member CastSpell.arrived_from] is an unordered
## set of every merged front's predecessor, so there is no "first" front: the
## reducer's single [member CastSpell.predecessor] is never consulted.
##
## First hit doesn't crit: the seed's [member CastSpell.arrived_from] is
## empty. An edge hop into a node with a self-loop also doesn't crit: the
## arrival is the upstream node, not the target. An unmerged landing has a
## one-element set, so single-front behaviour is unchanged.

func evaluate(lctx: LandingContext) -> bool:
	var state := lctx.payload
	var target := lctx.node
	if state == null or target == null:
		return false
	return state.arrived_from.has(target)


func get_description() -> String:
	return "across a self-loop"
