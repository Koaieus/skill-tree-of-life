class_name RunConfig
extends Resource

## What run to build — mode, level, seed, participants. Menus write this;
## the level reads it. `seed == 0` is a legal authoring value ("randomise
## me") that GameSession resolves to a concrete number exactly once, up
## front, before a run starts.

enum Mode { SINGLE, COOP_HOTSEAT, VERSUS }

@export var mode: Mode = Mode.SINGLE
@export var level_scene: PackedScene = null
@warning_ignore("shadowed_global_identifier")
@export var seed: int = 0
@export var participants: Array[Participant] = []
## Replaces the old n_random_starters: AI starters minus human participants.
@export var ai_opponent_count: int = 4
## How this run ends (#460). Null means "use the mode's default" — see
## [method default_condition_for]. Authored per-run rather than baked into
## [VictorySystem] because, per the owner, multiplayer setups will want
## different conditions.
@export var victory_condition: VictoryCondition = null


## The one and only place a seed sentinel resolves (#457). `0` means
## "randomise me"; any other value passes through untouched, so the function
## is idempotent — resolving an already-resolved seed is a no-op, which is
## what makes "re-reading does not re-randomise" true by construction.
##
## Static, and living on [RunConfig] rather than on the `GameSession` autoload,
## because `@tool` editor code (the procgen playground) has to reach it and
## project autoloads are not in the editor's tree.
static func resolve_seed(value: int) -> int:
	if value != 0:
		return value
	var drawn := randi()
	# 0 is the sentinel, so it must never survive as a resolved value.
	return drawn if drawn != 0 else 1


## The condition a mode falls back to when none is authored. All three modes
## share last-camp-standing today — the switch exists because the owner's call
## was explicitly that they "may default differently", and a mode wanting its
## own answer should find one place to change, not a call site to fork.
static func default_condition_for(_mode: Mode) -> VictoryCondition:
	return LastCampStandingCondition.new()


## The condition actually in force for this config.
func resolved_victory_condition() -> VictoryCondition:
	return victory_condition if victory_condition != null else default_condition_for(mode)
