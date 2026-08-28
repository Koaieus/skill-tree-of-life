class_name Scenario
extends Resource

## What game are we playing (#597 D9), as opposed to [RunConfig] — "who is
## playing it, right now". Authored as a handful of `.tres` under
## `session/scenarios/`, pickable and shareable like any other resource;
## [member RunConfig.scenario] points at one rather than duplicating its
## choices into every run.
##
## The direction test that settles which type holds which field (#597's own
## framing): could a [Scenario] `.tres` sensibly carry a `participants` array?
## No — participants carry peer ids, picked colours, picked camps. That is
## lobby OUTPUT, never authored content.
##
## No mode field (#597 D11a) — [method LobbyScreen.resolve_mode] stays the sole
## mode authority, deriving it from the roster at press time. A [Scenario]
## cannot know in advance how many humans will end up sharing a camp.
##
## Since #638 this is also where the victory condition lives: how a run ENDS is
## a fact about what game you are playing, not about who is playing it.

## The composed procgen shape this scenario generates (#349). A composed
## [GraphProcgenConfig] — five module refs plus a seed — never edited through
## this reference, only pointed at. Consumed by whichever level scene below
## generates the map (today, always `scenes/procgen_play_sandbox.gd`, the
## script `scenes/level.tscn` and its sandboxes share).
@export var preset: GraphProcgenConfig

## The level scene a run carrying this [Scenario] routes to (#584 D5). Read by
## `scenes/meta/meta_root.gd`'s START handler — moving the field off
## [RunConfig] without moving its reader would relocate #584 D5's smell
## instead of discharging it.
##
## [b]Must never name a scene whose own [RunBootstrap] holds a run pointing
## back at THIS Scenario.[/b] Godot's resource loader cannot resolve that
## cycle — `res://scenes/procgen_play_sandbox.tscn`'s `RunBootstrap` holds
## `session/runs/procgen_play_run.tres`, which is why
## `session/scenarios/procgen_play.tres` points here at `scenes/level.tscn`
## instead of at the sandbox scene it is bootstrapped from: pointing it at
## itself failed at load with "referenced non-existent resource", not at
## generation time. A `Scenario` meant only for a `RunBootstrap` sandbox with
## no lobby route can leave this null instead.
@export var level_scene: PackedScene


## How a run carrying this [Scenario] ends (#638, #597 D9). Null means "the
## default" — see [method resolved_victory_condition]. It sits here rather than
## on [RunConfig] because a victory condition is authored content, exactly like
## [member preset]: two runs of the same scenario end the same way, and a lobby
## that lets the host retune it does so as an override of THIS value, never as a
## second authoritative home for it.
@export var victory_condition: VictoryCondition = null


## The condition actually in force, falling back to this Scenario's OWN default.
##
## [b]Deliberately not a function of [enum RunConfig.Mode][/b] (#638 acceptance
## 2). The deleted `RunConfig.default_condition_for(mode)` was a `mode ->
## condition` switch, which is `Mode` deciding CONTENT — forbidden by
## `docs/domain/seat-policy.md` §"One axis" and #615 D6. A Scenario knows what
## game it is; the mode only knows how many humans share a machine, and #597
## D11a is explicit that a Scenario has no mode field at all. So the fallback is
## a property of the scenario and takes no arguments — a reintroduced mode
## switch has nowhere to hook.
func resolved_victory_condition() -> VictoryCondition:
	return victory_condition if victory_condition != null else default_victory_condition()


## The condition a [Scenario] authoring none falls back to. Static so callers
## with no [Scenario] at all (a `RunBootstrap` sandbox, #597 D6) resolve the
## SAME answer rather than a second, drifting one.
static func default_victory_condition() -> VictoryCondition:
	return LastCampStandingCondition.new()
