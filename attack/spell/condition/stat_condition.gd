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


## [method @GlobalScope.is_equal_approx] carries the "or equal" half, as in
## [RankThresholdFilter]: a score is a float even for an integer stat.
func evaluate(lctx: LandingContext) -> bool:
	if lctx == null or lctx.node == null or ranker == null:
		return false
	var score := ranker.score(lctx.node, lctx)
	var tied := is_equal_approx(score, threshold)
	match compare:
		RankThresholdFilter.Compare.LESS: return score < threshold and not tied
		RankThresholdFilter.Compare.LESS_OR_EQUAL: return score < threshold or tied
		RankThresholdFilter.Compare.GREATER: return score > threshold and not tied
		RankThresholdFilter.Compare.GREATER_OR_EQUAL: return score > threshold or tied
	return false


func get_description() -> String:
	var what := ranker.get_description() if ranker != null else ""
	if what == "":
		what = "rank"
	var how: String = {
		RankThresholdFilter.Compare.LESS: "below",
		RankThresholdFilter.Compare.LESS_OR_EQUAL: "at or below",
		RankThresholdFilter.Compare.GREATER: "above",
		RankThresholdFilter.Compare.GREATER_OR_EQUAL: "at or above",
	}.get(compare, "at")
	return "where its %s is %s %s" % [what, how, NumFmt.num(threshold)]
