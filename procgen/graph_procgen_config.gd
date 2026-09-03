@tool
class_name GraphProcgenConfig
extends Resource

## Bundle of knobs feeding [GraphProcgen]. Save as `.tres` under
## `procgen/presets/` to make a preset; the sandbox + future level pickers
## just take one of these and run.
##
## Thin composition of five module refs (#349) — the group boundaries
## `ec361e4` promoted are the module boundaries. Each module is authored as
## its own top-level `.tres` under `procgen/modules/<preset>/` and referenced
## here BY PATH, never embedded as a SubResource: a SubResource can't be
## swapped by a lobby at all, because there is nothing to point at (#349 D3),
## and that swap is what #597's override merge, #641's Scenario and #558's
## arrangement are all built on.
##
## `seed` and the Runtime group below are the exception: they are NOT
## authored content, so they stay on the config itself rather than moving
## into a module (#349 D4).

## RNG seed. 0 = randomise per run.
@warning_ignore("shadowed_global_identifier")
@export var seed: int = 0

@export_group("Modules")

## Node count / spacing / connectivity / self-loops. Map size XS..XXL.
##
## Defaults to a fresh [GraphProcgenTopology] (same for the other four module
## refs below) so `GraphProcgenConfig.new()` is usable out of the box, exactly
## as every scalar on the old flat resource had a default — a caller building
## a config from scratch (a test fixture, a bench harness) shouldn't have to
## know all five modules exist just to avoid a null-property crash. Loading an
## authored `.tres` always overrides this, same as any other export default.
@export var topology: GraphProcgenTopology = GraphProcgenTopology.new()
## The region procgen samples inside.
@export var shape: GraphProcgenShape = GraphProcgenShape.new()
## Authored starter anchors + random-starter / camp-placement knobs. Starter
## arrangement (#558).
@export var starting: GraphProcgenStartingPoints = GraphProcgenStartingPoints.new()
## Pools, weight profiles, budget, archetypes, addons, spell grants,
## placement + balancing. Budget min/max ("go HAM", #597 D8).
@export var content: GraphProcgenContent = GraphProcgenContent.new()
## Removable-blocker density + safety knobs (#300). Blockers None..Heavy.
@export var blockers: GraphProcgenBlockers = GraphProcgenBlockers.new()

# ── Runtime (stamped by the level, never authored) ─────────────────────────
# These fields sit where an author would expect them next to the modules
# above, but neither is authored content — it is written at runtime by the
# level from the [ParticipantRoster] and the scene
# (`scenes/procgen_play_sandbox.gd`), never crossing the wire, and each peer
# derives it independently. A module `.tres` on disk must never carry
# `camp_sizes` — that would make it a second source of truth against the
# roster (#349 D4).
##
## [b]`n_random_starters` / `viability_radius` used to live here[/b] (#349 D4)
## as the runtime-stamped inputs to the legacy, non-camp-aware random-fill
## branch of [method GraphProcgen.generate]. #742 lifted that branch into
## [CenterCoreStarters] (a real [StarterPlacement], camp-aware like
## [CampAnnulusStarters]) — `viability_radius` now lives on
## [member StarterPlacement.viability_radius], AUTHORED per placement
## instance rather than stamped, and the starter count is derived from
## [member camp_sizes] rather than tracked separately. Neither field survives
## here; a target naming either no longer resolves at all, which is a
## stronger guarantee than the deny-list [ScenarioOverride._RUNTIME_STAMPED_FIELDS]
## used to give them.
@export_group("Runtime (stamped by the level, never authored)")

## Runtime input set on the *duplicated* config by the level (exactly as
## [member seed] already is in `procgen_play_sandbox.gd`) — the roster's camp
## shape, translated out of its [Faction]s (procgen never sees a Faction).
## Inert unless [member GraphProcgenStartingPoints.starter_placement] is set.
@export var camp_sizes: Array[int] = []
