class_name RunBootstrap
extends Node

## Starts a run from an authored [RunConfig] when no composer did — the
## editor-launch half of #584.
##
## [b]This is a child node, deliberately, and it is the whole mechanism.[/b] A
## level scene that can be launched directly needs a run to consume, and there
## are three ways to give it one: a fallback branch inside the level (what this
## replaces), a virtual hook the sandbox subclass overrides (what `9b0e185`
## did), or a sibling that fills [GameSession] in before the level looks. Only
## the third leaves the level with [b]one[/b] way to learn what run it is
## generating, and that property is the point:
##
## [codeblock]
## lobby  → GameSession.start(composed RunConfig)  ┐
##                                                 ├→ level reads GameSession
## RunBootstrap → GameSession.start(authored .tres)┘
## [/codeblock]
##
## A sandbox that parsed its settings differently from a lobby-launched run
## would stop being a rehearsal of the real game — the owner's call, 2026-08-26:
## [i]"if our first level sandbox deviates from the 'lobby launched level' in a
## meaningful way (or in how it parses its settings) it becomes less of a real
## representative of the real game"[/i]. Here the two paths differ only in
## [b]who authored the RunConfig[/b], never in what the level does with it.
##
## The level never references this class. That is what makes it a rehearsal
## rather than an accommodation: `scenes/level.tscn` has no idea a bootstrap
## exists, so there is no sandbox-shaped seam in the shipped code for the two
## paths to drift apart along.
##
## [b]Ordering.[/b] A child's `_ready` runs before its parent's, and
## [method GameRoot._ready] is where the level reaches `_setup_level` — the only
## thing in a level's bring-up that reads [member GameSession.roster]. So the
## bootstrap wins that race wherever it sits, with no explicit call from
## [GameRoot] to keep in sync.
##
## It is nonetheless authored as the [b]first[/b] child (`index="0"`). Godot
## readies depth-first in tree order, so last-child would leave the guarantee
## resting on an audit — "nothing under `Graph` or `HudRoot` reads
## [member GameSession.config] in its own `_ready`" — that is true today and
## that a future sibling could quietly break, with the symptom being a null
## config rather than an error. First-child makes it true by layout instead:
## nothing in the level can observe a session this node has not opened yet.

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
