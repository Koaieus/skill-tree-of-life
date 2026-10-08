@tool
class_name ChokepointCondition
extends LandingCondition

## True when the landed node is a CHOKEPOINT — a cut vertex of its owner's
## territory, anchored at that owner's core: removing it would island some
## other node the owner holds from the core. Read against THIS cast's world
## ([method LandingContext.is_cut_vertex]), never a live [GraphMirror], so a
## kill on wave N changes which nodes are chokepoints on wave N+1
## (`.claude/rules/attack-timeline.md`).
##
## Girdle's crit: ring the bark and the limb beyond it withers.


func evaluate(lctx: LandingContext) -> bool:
	if lctx == null or lctx.node == null:
		return false
	return lctx.is_cut_vertex(lctx.node)


func get_description() -> String:
	return "on a chokepoint"
