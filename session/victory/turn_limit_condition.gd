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
## `level`, ties broken by the sum of their `xp` pool `current` — plain
## arithmetic, no level-curve math. An exact all-camps tie is a DRAW. The score
## lives in ONE private method because it "may become a knob later" (owner).
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
	var best: Faction = null
	var best_score := Vector2(-INF, -INF)
	var tied := false
	for camp in ctx.living_camps(contestants):
		var score := _camp_score(ctx, camp)
		if score > best_score:
			best = camp
			best_score = score
			tied = false
		elif score == best_score:
			tied = true
	return _outcome(ctx, null if tied else best)


## A camp's score as `(summed level, summed xp.current)`, compared
## lexicographically — the second component is the tiebreaker. Same three
## filters as [method VictoryContext.living_camps]: valid, living, contestant.
func _camp_score(ctx: VictoryContext, camp: Faction) -> Vector2:
	var levels := 0.0
	var xp := 0.0
	for ent in ctx.entities:
		if not is_instance_valid(ent) or ent.is_dead:
			continue
		if contestants != null and not contestants.includes(ent):
			continue
		if ent.faction == null or ent.faction.id != camp.id:
			continue
		if ent.stat_board == null:
			continue
		levels += ent.level
		if ent.stat_board.xp != null:
			xp += ent.stat_board.xp.current
	return Vector2(levels, xp)
