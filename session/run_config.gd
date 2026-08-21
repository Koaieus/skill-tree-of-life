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


## The condition a mode falls back to when none is authored. All three modes
## share last-camp-standing today — the switch exists because the owner's call
## was explicitly that they "may default differently", and a mode wanting its
## own answer should find one place to change, not a call site to fork.
static func default_condition_for(_mode: Mode) -> VictoryCondition:
	return LastCampStandingCondition.new()


## The condition actually in force for this config.
func resolved_victory_condition() -> VictoryCondition:
	return victory_condition if victory_condition != null else default_condition_for(mode)
