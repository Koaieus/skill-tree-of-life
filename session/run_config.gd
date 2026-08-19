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
