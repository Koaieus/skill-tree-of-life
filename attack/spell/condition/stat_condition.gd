@tool
class_name StatCondition
extends LandingCondition

## True when the landed node's [member ranker] score stands against a FIXED
## [member threshold] as [member compare] says — "score vs threshold", where
## [RankThresholdFilter] (whose enum this borrows) means "candidate vs current".
## Read through the [LandingContext], i.e. against THIS cast's world, so an
## earlier wave's Sunder moves the answer.

@export var ranker: NodeRanker = null
@export var compare: RankThresholdFilter.Compare = RankThresholdFilter.Compare.LESS_OR_EQUAL
@export var threshold: float = 0.0


func evaluate(_lctx: LandingContext) -> bool:
	return false
