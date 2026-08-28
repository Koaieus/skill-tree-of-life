class_name VictoryCondition
extends Resource

## When does a run end, and who won? An authored, swappable rule — the owner's
## call (2026-08-21) was that last-camp-standing is "the first and the default,
## not the only one", because multiplayer setups will want different
## conditions. [member Scenario.victory_condition] carries the chosen one
## (#638 moved it off RunConfig, which now only resolves it).
##
## Pure: [method evaluate] reads a [VictoryContext] and returns either a
## populated [RunOutcome] (the run is over) or [code]null[/code] (it continues).
## It must not mutate the world, emit signals, or route scenes — [VictorySystem]
## owns all of that, and owns the once-only latch.
##
## The outcome it returns is **point-of-view-free** (#517): it names the winning
## camp and nothing else. Whether that reads as a win or a loss on some screen
## is a presentation question, answered by [HudRoot] from the local
## [SeatPolicy] — a run has one winner and as many points of view as there are
## machines watching.

## Who is in the contest at all (#517). Defaults to the shipped rule excluding
## the `scenery` group, so a level that authors nothing still ignores dormant
## cores. A script-default [Resource] is shared across every instance in Godot;
## that is safe here precisely because a [ContestantRule] is a pure predicate
## with no per-run state.
##
## A null rule means EVERYONE counts — never a crash and never a run that can
## no longer end.
@export var contestants: ContestantRule = preload("res://session/victory/rules/exclude_scenery.tres")


## Override. Return null while the run continues.
func evaluate(_ctx: VictoryContext) -> RunOutcome:
	return null


## Fills the shared tail of every outcome, so a subclass only decides the
## winner. [param winner] null means nobody won (a mutual wipe → DRAW).
func _outcome(ctx: VictoryContext, winner: Faction) -> RunOutcome:
	var outcome := RunOutcome.new()
	outcome.winning_camp = winner
	outcome.turn_count = ctx.turn_count
	return outcome
