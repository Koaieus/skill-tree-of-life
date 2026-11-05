class_name RunBootstrap
extends Node

## Starts a run from an authored `RunConfig` when no composer did (the
## editor-launch half). A child node, authored as the FIRST child, so it opens
## `GameSession` before the level reads it; the level never references this class,
## so sandbox and lobby-launched runs differ only in who authored the config.
## See docs/domain/lobby.md

## The run this scene starts itself with. Authored `.tres` under `session/runs/`.
##
## Unset is a misconfiguration, not a mode — a scene carrying a bootstrap is
## by definition one that means to start its own run.
@export var run_setup: RunConfig


func _ready() -> void:
	# A live session outranks an authored one, and this is not merely defensive.
	# The pause menu restarts via `reload_current_scene`, which rebuilds this
	# node with the run still open; re-starting here would reroll the seed and
	# silently replace the map the player asked to retry. `GameSession.start`
	# resolving the seed exactly once per run (#457) is the invariant that
	# protects, and it is [GameSession]'s to keep, not this node's to re-do.
	if GameSession.is_active():
		return
	if run_setup == null:
		push_error("RunBootstrap: `run_setup` is unset — this scene starts no run, "
				+ "so the level below it will find no roster and refuse to generate.")
		return
	# Clone at consumption. `duplicate(true)` copies the Participants but leaves
	# each one's `camp` pointing at the same authored Faction `.tres`, because
	# external resources are not deep-copied — verified under GUT on #584,
	# and load-bearing: `ParticipantRoster.camps()` dedupes by object identity,
	# so deep-copying the Faction would turn two allies sharing camp_1 into two
	# distinct camps and silently make them rivals.
	GameSession.start(run_setup.duplicate(true) as RunConfig)
