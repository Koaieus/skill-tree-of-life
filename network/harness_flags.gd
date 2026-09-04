class_name HarnessFlags
extends RefCounted

## The multiplayer harness's command-line vocabulary, in one place.
##
## Everything here is read from [method OS.get_cmdline_user_args] — the tail
## after a bare `--`, which the engine never touches — and every reader returns
## its fallback when the flag is absent. That is the whole contract the rung-3
## flag established and rung 4 inherits: [b]an ordinary launch, an exported
## build and the GUT suite parse nothing and print nothing[/b], because a
## harness that changed behaviour without being asked would be a harness nobody
## could trust the shipped route against (#715, #754).
##
## Two forms, both accepted by the same scan:
##
## [codeblock]
##   --autoplay              bare  -> `has()`
##   --max-turns=200         pair  -> `value()` / `number()`
## [/codeblock]
##
## It exists as one class rather than a parser per reader because the flags are
## read from BOTH halves of the route — [MetaRoot] drives the lobby, [GameRoot]
## drives the run — and two scanners of the same argv drift the moment a third
## flag lands. See `docs/domain/multiplayer-harness.md`.

## Which end of the link this process is: `host`, `client`, or `""` when this is
## an ordinary launch. The flag rung 3 is named after; everything else here is
## only ever read alongside a non-empty role.
const LOBBY := "lobby"
const ADDRESS := "address"
const PORT := "port"
## Rung 4: the host hands every human seat to the AI at the first turn, both
## ends print a verdict on `run_ended`, and the process quits.
const AUTOPLAY := "autoplay"
## The entity-turn budget an autoplay run may spend before it is called a
## timeout ([member TurnManager.turns_taken] counts ENTITY turns, not rounds).
const MAX_TURNS := "max-turns"


## `--<name>=<v>` -> `v`; `--<name>` alone -> `""`; absent -> [param fallback].
##
## Last occurrence wins, matching what a shell user expects from repeating a
## flag, and unrelated arguments are skipped rather than rejected — the harness
## shares argv with whatever else a launcher appends.
static func value(name: String, fallback: String = "") -> String:
	var found := fallback
	for arg in OS.get_cmdline_user_args():
		var body := arg.trim_prefix("--")
		if body == name:
			found = ""
		elif body.begins_with(name + "="):
			found = body.substr(name.length() + 1)
	return found


## Is the flag present at all, in either form?
static func has(name: String) -> bool:
	return value(name, " ") != " "


## `--<name>=<int>`, or [param fallback] when absent or not a number. A flag
## given without a value keeps the fallback too: `--max-turns` with nothing
## after it is a typo, and a silent `0` would end the run before it began.
static func number(name: String, fallback: int) -> int:
	var raw := value(name)
	return fallback if not raw.is_valid_int() else int(raw)
