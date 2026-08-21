class_name VictoryCondition
extends Resource

## When does a run end, and who won? An authored, swappable rule — the owner's
## call (2026-08-21) was that last-camp-standing is "the first and the default,
## not the only one", because multiplayer setups will want different
## conditions. [RunConfig.victory_condition] carries the chosen one.
##
## Pure: [method evaluate] reads a [VictoryContext] and returns either a
## populated [RunOutcome] (the run is over) or [code]null[/code] (it continues).
## It must not mutate the world, emit signals, or route scenes — [VictorySystem]
## owns all of that, and owns the once-only latch.

## Override. Return null while the run continues.
func evaluate(_ctx: VictoryContext) -> RunOutcome:
	return null


## Fills the shared tail of every outcome, so a subclass only decides the
## winner. [param winner] null means nobody won (a mutual wipe → DRAW).
func _outcome(ctx: VictoryContext, winner: Faction) -> RunOutcome:
	var outcome := RunOutcome.new()
	outcome.winning_camp = winner
	outcome.turn_count = ctx.turn_count
	# DRAW covers both "nobody won" and "there is no local human to have won"
	# (an AI-only or headless run) — the run still ended and still names its
	# winner in `winning_camp`; only the local point of view is absent.
	if winner == null or ctx.local_camp == null:
		outcome.local_result = RunOutcome.LocalResult.DRAW
	elif ctx.is_local_camp(winner):
		outcome.local_result = RunOutcome.LocalResult.WIN
	else:
		outcome.local_result = RunOutcome.LocalResult.LOSS
	return outcome
