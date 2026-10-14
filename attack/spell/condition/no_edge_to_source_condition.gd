@tool
class_name NoEdgeToSourceCondition
extends LandingCondition

## True when the hit flew in from a blast centre that shares no graph edge
## with the landed node — the wave jumped a gap. The centre is the payload's
## `predecessor`, never `lctx.origin` (which falls back to the cast-from node
## on the seed); a null predecessor, the seed, never crits. Under a
## per-incident reducer it is asked once per incoming hit.


func evaluate(lctx: LandingContext) -> bool:
	return false


func get_description() -> String:
	return "across a gap: the blast's centre shares no edge with the node"
