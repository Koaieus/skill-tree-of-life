@tool
class_name LocalExtremumCondition
extends LandingCondition

## True when the landed node is a LOCAL EXTREMUM of [member ranker]: its score
## is ≥ ([enum Mode] MAX) or ≤ (MIN) every counted neighbour's. Ties count, so a
## plateau's every node is a summit. Scores are read through the
## [LandingContext], i.e. against THIS cast's world, so an earlier wave's Sunder
## or kill moves the answer on a later wave (`.claude/rules/attack-timeline.md`).
##
## A neighbour counts when its [method LandingContext.ownership_bit_of] meets
## [member neighbours]; self-loop edges never count. A node with NO counted
## neighbour is vacuously an extremum — there is nothing above (or below) it.
##
## Rend's summit crit (MAX of armor); Fault Line's weak point (MIN).

enum Mode { MAX, MIN }

## What is compared — a [StatRanker] for a stat summit.
@export var ranker: NodeRanker = null
## MAX: ≥ every counted neighbour. MIN: ≤ every counted neighbour.
@export var mode: Mode = Mode.MAX
## Which neighbours count, by ownership relative to the caster. Default:
## allocated ones only, so an unallocated neighbour never spoils a summit.
## Tentative, easy to change.
@export_flags("Neutral:1", "Mine:2", "Ally:4", "Hostile:8", "Friendly:6", "Allocated:14", "Any:15")
var neighbours: int = 14


func evaluate(lctx: LandingContext) -> bool:
	if lctx == null or lctx.node == null or ranker == null or lctx.cast == null or lctx.cast.graph == null:
		return false
	var here := ranker.score(lctx.node, lctx)
	for n in lctx.cast.graph.get_neighbours(lctx.node):
		if n == lctx.node or lctx.ownership_bit_of(n) & neighbours == 0:
			continue
		var there := ranker.score(n, lctx)
		if (mode == Mode.MAX and there > here) or (mode == Mode.MIN and there < here):
			return false
	return true


func get_description() -> String:
	var what := ranker.get_description() if ranker != null else ""
	if what == "":
		what = "rank"
	return "where its %s is %s among its neighbours" % [what, "highest" if mode == Mode.MAX else "lowest"]
