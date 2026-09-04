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
## Seconds an AI pauses before acting. Autoplay pins it to 0 so a run costs
## seconds rather than minutes — which is also a pace no human has ever played
## this path at, so it is overridable: `--ai-delay=0.4` is how "does this only
## break when commands arrive back to back?" gets asked without editing code
## (#756).
const AI_DELAY := "ai-delay"


## `--<name>=<v>` -> `v`; `--<name>` alone -> `""`; absent -> [param fallback].
##
## Last occurrence wins, matching what a shell user expects from repeating a
## flag, and unrelated arguments are skipped rather than rejected — the harness
## shares argv with whatever else a launcher appends.
##
## [param args] defaults to this process's own tail and exists so the scan can
## be tested: a parser whose only input is the real argv can only be checked by
## launching a process, which is precisely the cost this class is here to keep
## out of the suite.
static func value(
	name: String, fallback: String = "", args: PackedStringArray = OS.get_cmdline_user_args()
) -> String:
	var found := fallback
	for arg in args:
		var body := arg.trim_prefix("--")
		if body == name:
			found = ""
		elif body.begins_with(name + "="):
			found = body.substr(name.length() + 1)
	return found


## Is the flag present at all, in either form? The sentinel is a space, which no
## shell word can be — a bare `--autoplay` yields `""`, so "absent" and "present
## with no value" cannot be told apart by an empty-string check.
static func has(name: String, args: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	return value(name, " ", args) != " "


## `--<name>=<int>`, or [param fallback] when absent or not a number. A flag
## given without a value keeps the fallback too: `--max-turns` with nothing
## after it is a typo, and a silent `0` would end the run before it began.
static func number(
	name: String, fallback: int, args: PackedStringArray = OS.get_cmdline_user_args()
) -> int:
	var raw := value(name, "", args)
	return fallback if not raw.is_valid_int() else int(raw)


## The same, for a flag measured in seconds. Accepts an integer too — `1` is a
## legal number of seconds, and `is_valid_float` says so.
static func decimal(
	name: String, fallback: float, args: PackedStringArray = OS.get_cmdline_user_args()
) -> float:
	var raw := value(name, "", args)
	return fallback if not raw.is_valid_float() else float(raw)
