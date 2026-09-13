@tool
class_name JunctionCondition
extends LandingCondition

## True when the landed node is a JUNCTION — three or more of its owner's own
## edges meet there ([b]entity[/b] degree > 2), as read against THIS cast's
## world ([method LandingContext.entity_degree_of], #860) rather than off the
## live node.
##
## Entity degree, never graph degree, and that is the spell's premise rather
## than an implementation detail: the Trailblazer is about the DEFENDER's
## constellation shape, so an unrelated enemy node brushing past the string
## must not read as a junction. This is the identical read
## [TrailBlazerSpread] made inline until #851 — see `docs/domain/degree.md`.
##
## And it must be the world's count, not the node's: a Trailblazer whose own
## earlier hop deallocated a neighbour must not still count that neighbour
## toward "is this a junction" — the slam would fire on a junction that no
## longer exists.
##
## Drives both halves of the Trailblazer's ending: the [ScaleDamageEffect]
## slam that fires here, and (as the mirrored `from_entity_degree <= 2` clause
## on the spell's [ExpressionFilter]) the fact that the walk cannot leave.


func evaluate(lctx: LandingContext) -> bool:
	var state := lctx.payload
	var target := lctx.node
	if state == null or target == null or state.graph == null:
		return false
	return lctx.entity_degree_of(target) > 2


func get_description() -> String:
	return "at a junction"
