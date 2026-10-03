class_name TurnLimitCondition
extends VictoryCondition

## After [member limit] rounds (or entity-turns, per [member unit]), the camp
## with the highest score wins (#1257). Ships as a BONUS under
## [CombinedVictoryCondition] (`session/victory/turn_limit.tres`), so
## last-camp-standing still ends a run early.
##
## **Owner, 2026-09-30:** "perhaps a new victorycondition: turn limit. after
## that, pick the one with highest total XP (or level + xp bar tiebreaker
## whichever's easier)". A camp's score is the sum of its living contestants'
## lifetime XP ([method GrowablePoolStat.total] — the owner's 2026-10-03 pick,
## since level and bar don't add across several members), ties broken by the
## nodes they own (owner, 2026-10-02: "tiebreak owned territory sounds fitting
## tho"). An exact tie on both is a DRAW. The score lives in ONE private method
## because it "may become a knob later" (owner).
##
## Pure: reads only the [VictoryContext], never the [TurnManager].

## What [member limit] counts. ROUNDS is the classic initiative round
## ([member VictoryContext.rounds_completed]); ENTITY_TURNS is every turn served
## ([member VictoryContext.turn_count]).
enum Unit { ROUNDS, ENTITY_TURNS }

## How many [member unit]s the run lasts. Tentative default (owner, 2026-10-01:
## "Then 20 rounds for the default. Or 15").
@export_range(1, 500) var limit: int = 15
## What [member limit] counts — rounds by default (owner, 2026-09-30).
@export var unit: Unit = Unit.ROUNDS


func evaluate(ctx: VictoryContext) -> RunOutcome:
	var elapsed := ctx.rounds_completed if unit == Unit.ROUNDS else ctx.turn_count
	if elapsed < limit:
		return null
	var territory := _territory_by_camp(ctx)
	var best: Faction = null
	var best_score := Vector2(-INF, -INF)
	var tied := false
	for camp in ctx.living_camps(contestants):
		var score := _camp_score(ctx, camp, territory)
		if score > best_score:
			best = camp
			best_score = score
			tied = false
		elif score == best_score:
			tied = true
	return _outcome(ctx, null if tied else best)


func describe() -> String:
	if unit == Unit.ROUNDS:
		return "Turn limit (%d rounds)" % limit
	return "Turn limit (%d entity turns)" % limit


## A camp's score as `(summed lifetime XP, owned nodes)`, compared
## lexicographically — territory breaks a tie in XP. [param territory] is
## [method _territory_by_camp]'s one walk, shared by every camp.
func _camp_score(ctx: VictoryContext, camp: Faction, territory: Dictionary) -> Vector2:
	var xp := 0.0
	for ent in ctx.entities:
		if not _scores(ent) or ent.faction.id != camp.id:
			continue
		if ent.stat_board == null:
			continue
		var pool := ent.stat_board.xp as GrowablePoolStat
		if pool != null:
			xp += pool.total()
	return Vector2(xp, territory.get(camp.id, 0))


## Owned nodes per camp id, in ONE walk of the graph (never one per camp). A
## null graph is no territory for anyone.
func _territory_by_camp(ctx: VictoryContext) -> Dictionary:
	var counts := {}
	if ctx.graph == null:
		return counts
	for node in ctx.graph.get_skill_nodes():
		var owner := node.owned_by
		if _scores(owner):
			counts[owner.faction.id] = counts.get(owner.faction.id, 0) + 1
	return counts


## Whether [param ent] counts toward its camp's score — the same filters as
## [method VictoryContext.living_camps]: valid, living, contestant, in a camp.
func _scores(ent: Entity) -> bool:
	if not is_instance_valid(ent) or ent.is_dead or ent.faction == null:
		return false
	return contestants == null or contestants.includes(ent)
