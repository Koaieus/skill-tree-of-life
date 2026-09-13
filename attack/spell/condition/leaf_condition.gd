@tool
class_name LeafCondition
extends LandingCondition

## True when the target is a leaf of ITS OWNER'S territory — degree 1 within
## the owner's induced subgraph, the same metric [RankThresholdFilter] +
## [DegreeRanker] compare. A node whose only other neighbour belongs to someone
## else dangles off its owner's land and counts as a leaf, even though its
## whole-graph degree is 2. See `docs/domain/degree.md`.
##
## Read against THIS cast's world ([method LandingContext.entity_degree_of],
## #860), not off the live node — a node this same cast made a leaf on an
## earlier wave (by deallocating its other neighbour) must read as one here,
## even though the live node still reports its pre-cast degree.


func evaluate(lctx: LandingContext) -> bool:
	var state := lctx.payload
	var target := lctx.node
	if target == null or state == null or state.graph == null:
		return false
	return lctx.entity_degree_of(target) == 1


func get_description() -> String:
	return "on a leaf of its owner's territory"
