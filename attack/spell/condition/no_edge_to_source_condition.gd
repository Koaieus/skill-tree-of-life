@tool
class_name NoEdgeToSourceCondition
extends LandingCondition

## True when the hit flew in from a blast centre that shares no graph edge
## with the landed node — the wave jumped a gap. The centre is the payload's
## `predecessor`, never `lctx.origin` (which falls back to the cast-from node
## on the seed); a null predecessor, the seed, never crits. Under a
## per-incident reducer it is asked once per incoming hit.


func evaluate(lctx: LandingContext) -> bool:
	if lctx == null or lctx.payload == null or lctx.node == null:
		return false
	var centre := lctx.payload.predecessor
	if centre == null or lctx.cast == null or lctx.cast.graph == null:
		return false
	return not lctx.cast.graph.get_neighbours(lctx.node).has(centre)


func get_description() -> String:
	return "across a gap: the blast's centre shares no edge with the node"
