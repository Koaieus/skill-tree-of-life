@tool
class_name RankThresholdFilter
extends PropagationFilter

## Compares each candidate's [NodeRanker] score against the CURRENT node's on
## the same metric. The one implementation of "candidate vs current on a
## metric" — it absorbed both the old `DegreeFilter` (degree, hardcoded) and
## the old `CurrentThresholdPass` (any ranker, but buried inside
## [TakeTopNSpread]) in #850. Pair it with [DegreeRanker] for the degree-flow
## spells (Leafblower, Reverberator), with any other ranker for the rest.
##
## Pairwise, so the inherited [method PropagationFilter.narrow] loop is the
## whole implementation.

## Kept in this order deliberately: the shipped `.tres` files store the enum by
## ordinal, and these ordinals are the ones `DegreeFilter` used.
enum Compare {
	LESS,            ## candidate < current (one hop off a peak, no further)
	LESS_OR_EQUAL,   ## candidate ≤ current (Leafblower — downhill or plateau)
	GREATER,         ## candidate > current (strict climber)
	GREATER_OR_EQUAL, ## candidate ≥ current (Reverberator — uphill or plateau)
}

@export var ranker: NodeRanker = null
@export var compare: Compare = Compare.LESS


## NOTE on [constant LESS] / [constant GREATER] with [DegreeRanker]: a strict
## comparison cannot traverse a chain at all — every interior node of a path
## has degree 2, so the walk stalls one hop past the seed. Leafblower ships
## [constant LESS_OR_EQUAL] for exactly that reason. Plateau-looping is not a
## risk either way: [member PropagationConfig.max_visits_per_node] terminates
## the walk.
##
## With [DegreeRanker] each endpoint is measured in its OWN owner's subgraph
## (entity degree, see [code].claude/rules/degree.md[/code]); in a 3-way fight
## [param from] and [param to] can therefore be compared across two
## subgraphs. That's intended — "downhill" means downhill relative to the land
## each node actually sits in. Self-loops count +2 on both sides, so a
## fortified node genuinely reads as higher-degree and turns the walk away.
## Degenerate case worth naming: with a null [member PropagationContext.graph]
## a [DegreeRanker] scores 0.0 on both sides, so the "or equal" compares admit
## rather than refuse (the old hardcoded `DegreeFilter` refused outright). No
## shipped `.tres` and no test resolves without a graph.
func allows(from: SkillNode, to: SkillNode, payload: CastSpell, ctx: PropagationContext) -> bool:
	if ranker == null or from == null or to == null:
		return false
	var cur := ranker.score(from, payload, ctx)
	var nb := ranker.score(to, payload, ctx)
	# Scores are floats even when the metric is an integer degree, so the
	# "or equal" half goes through [method @GlobalScope.is_equal_approx]
	# rather than `==`.
	var tied := is_equal_approx(nb, cur)
	match compare:
		Compare.LESS: return nb < cur and not tied
		Compare.LESS_OR_EQUAL: return nb < cur or tied
		Compare.GREATER: return nb > cur and not tied
		Compare.GREATER_OR_EQUAL: return nb > cur or tied
	return false


## Draft copy — #764 rewrites all stage copy into player words in one pass.
func get_description() -> String:
	var metric := ranker.get_description() if ranker != null else "rank"
	match compare:
		Compare.LESS: return "Only into lower %s than the current node." % metric
		Compare.LESS_OR_EQUAL: return "Only into equal or lower %s." % metric
		Compare.GREATER: return "Only into higher %s than the current node." % metric
		Compare.GREATER_OR_EQUAL: return "Only into equal or higher %s." % metric
	return ""
