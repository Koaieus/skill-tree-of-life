class_name RunConfig
extends Resource

## What run to build — mode, scenario, seed, participants. Menus write this;
## the level reads it. `seed == 0` is a legal authoring value ("randomise
## me") that GameSession resolves to a concrete number exactly once, up
## front, before a run starts.

enum Mode { SINGLE, COOP_HOTSEAT, VERSUS }

@export var mode: Mode = Mode.SINGLE
## What game this run is playing (#641) — the composed procgen preset and the
## level scene to route to. Replaces the old `level_scene` field: a Scenario
## is authored content, pickable and shareable, and a run points at one rather
## than duplicating its choices. Null is legal — a directly-launched sandbox's
## `RunBootstrap` fixture may open a session with no Scenario at all, and the
## level it boots falls back to its own scene-authored `preset` (#597 D6).
@export var scenario: Scenario = null
## Leaf-addressed by-value patches (#642 D14) merged onto a DUPLICATE of
## [member scenario]'s `preset` — never a write to the authored asset. See
## [ScenarioOverride] and [method resolved_preset]. An empty array (the
## common case — most runs pick a named preset with no tweaks) means
## "the authored preset, unchanged" by construction: there is no sentinel to
## check, only entries to apply.
@export var overrides: Array[ScenarioOverride] = []
@warning_ignore("shadowed_global_identifier")
@export var seed: int = 0
@export var participants: Array[Participant] = []


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


## How this run ends — read straight off [member scenario] (#638). The field
## and the mode-keyed default switch that used to live beside it are GONE,
## not merely uncalled (see [method Scenario.default_victory_condition] for the
## name that was deleted and why): a victory condition is authored content, so it
## belongs to "what game is this" ([Scenario]) and never to a [enum Mode],
## which decides only how many humans share a machine (#615 D6,
## `docs/domain/seat-policy.md` §"One axis").
##
## Kept as a method on [RunConfig] because that is the seam `scenes/game_root.gd`
## already reads, and because a run with NO scenario (a `RunBootstrap` sandbox,
## #597 D6) still has to end somehow — it resolves the same default a
## condition-less [Scenario] does, from the same static.
func resolved_victory_condition() -> VictoryCondition:
	if scenario == null:
		return Scenario.default_victory_condition()
	return scenario.resolved_victory_condition()


## The preset this run actually generates from (#642 D14) — [member scenario]'s
## authored `preset` with every entry in [member overrides] merged onto a
## DUPLICATE of the whole [Scenario] (see [method ScenarioOverride.merge_onto];
## the authored asset and its modules are never mutated — #742 rooted the
## merge at [Scenario] rather than at `preset` directly, so this reads `.preset`
## back off that merged duplicate instead of merging onto `preset` itself).
## Null [member scenario] (or a Scenario with no `preset`) yields null, same
## shape as [method resolved_victory_condition]'s null-falls-to-default — here
## the level falls back to its own scene-authored preset instead (#597 D6),
## one layer up from this function.
func resolved_preset() -> GraphProcgenConfig:
	if scenario == null or scenario.preset == null:
		return null
	return ScenarioOverride.merge_onto(scenario, overrides).preset


## Wire form for #528 — "the run's shape crosses the wire; each peer derives
## its own seat" (the acceptance spec's own framing). [member scenario] crosses
## as a resource PATH: it is either unset or points at one of a handful of
## authored `.tres` assets, so there is no per-node-scale string cost to intern
## away here (contrast #527's per-node archetype/addon refs, where that cost is
## real). The victory condition no longer crosses at all — since #638 it hangs
## off that [Scenario], so a peer that loaded the same scenario path resolves
## the same condition by construction rather than by a second field agreeing.
## [member seed] rides along even though the graph itself is
## now serialized (#527) — it's no longer needed to reproduce the map, but
## other things read it, and a peer whose session reports a different seed
## than the host's is worth being able to see (#528's acceptance spec).
##
## [b]Every script variable declared on this class must be a key below.[/b]
## `test_run_config_wire_guard.gd` walks [method get_property_list] and fails
## on any field that is neither a key here nor on that test's named deny-list
## — #597's trap: an `@export` this function never learned about crosses as
## nothing, and the client silently generates from a null value.
func to_dict() -> Dictionary:
	var participant_rows: Array = []
	for p in participants:
		participant_rows.append(p.to_dict())
	var override_rows: Array = []
	for o in overrides:
		override_rows.append(o.to_dict())
	return {
		"mode": mode,
		"scenario": scenario.resource_path if scenario != null else "",
		"overrides": override_rows,
		"seed": seed,
		"participants": participant_rows,
	}


static func from_dict(d: Dictionary) -> RunConfig:
	var cfg := RunConfig.new()
	cfg.mode = int(d.get("mode", Mode.SINGLE)) as Mode
	var scenario_path := String(d.get("scenario", ""))
	cfg.scenario = load(scenario_path) as Scenario if scenario_path != "" else null
	var override_rows: Array = d.get("overrides", [])
	var overrides_out: Array[ScenarioOverride] = []
	for row in override_rows:
		overrides_out.append(ScenarioOverride.from_dict(row as Dictionary))
	cfg.overrides = overrides_out
	cfg.seed = int(d.get("seed", 0))
	var parts: Array[Participant] = []
	for row in (d.get("participants", []) as Array):
		parts.append(Participant.from_dict(row as Dictionary))
	cfg.participants = parts
	return cfg
