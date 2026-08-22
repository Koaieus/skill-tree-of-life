extends Node

## The live run (#457): what was asked for ([RunConfig]), who is in it
## ([ParticipantRoster]), and how it ended ([RunOutcome]). An autoload, so a
## level can read the run it belongs to across the menu→level scene swap
## without a hand-carried node.
##
## [b]Its one hard job is the determinism contract.[/b] [member RunConfig.seed]
## is resolved EXACTLY ONCE, up front, in [method start] — before any level
## builds. `seed == 0` is the authoring sentinel for "randomise me"; every
## consumer downstream reads the concrete resolved value off
## [code]GameSession.config.seed[/code], so a good run can be replayed by
## typing its seed back into the lobby.
##
## [b]The seed is for procgen. Nothing else.[/b] Owner call, 2026-08-21 (#457),
## verbatim: [i]"we don't care about that seed beyond the procgen using it, for
## now. possibly forever."[/i] Combat reproducibility comes from the per-attack
## [member AttackPlan.resolve_seed] stamped by [BattleSystem] (`8dc6f77`), and
## loot rolls are deliberately host-only per #473 — see
## [code]test/unit/attack/test_attack_determinism.gd[/code], which pins that on
## purpose. So: [b]the same seed reproduces the same MAP, not the same
## FIGHTS.[/b] That is the normal roguelike bargain and an explicit choice.
## Do NOT thread this seed into [BattleSystem], [SpellResolver], [LootSystem]
## or [SkillDustAddon].

## Fired once a run's config is settled and its seed resolved.
signal run_started(config: RunConfig)
## Fired when the run's terminal state has been recorded here.
signal run_recorded(outcome: RunOutcome)

## The run being played. Null between runs. Its `seed` is always concrete
## (non-zero) while a run is live.
var config: RunConfig = null

## Who is in the run. Levels that build their own roster (the procgen
## sandboxes, until #461 makes the lobby feed it) hand it back here.
var roster: ParticipantRoster = null

## How the run ended, recorded off [signal Events.run_ended]. Null until then.
var outcome: RunOutcome = null


func _ready() -> void:
	Events.run_ended.connect(_on_run_ended)


func is_active() -> bool:
	return config != null


## Begin a run. Resolves the seed sentinel once, here, and nowhere else.
## The lobby's START calls this immediately before routing to the level.
func start(cfg: RunConfig) -> void:
	assert(cfg != null, "GameSession.start: null RunConfig")
	config = cfg
	config.seed = RunConfig.resolve_seed(config.seed)
	roster = ParticipantRoster.new()
	outcome = null
	run_started.emit(config)


## Start a default run if none is live, seeding it from `fallback_seed` (a
## level scene's authored preset seed; 0 means "randomise me" as usual).
##
## This is how a level launched directly — a dev sandbox, a test, `godot
## --path . scenes/procgen_play_sandbox.tscn` — still gets exactly one resolved
## seed without a lobby. A run that IS live is left alone, which is a
## deliberate choice with one visible consequence: the pause menu's restart
## (`reload_current_scene`) replays the SAME map rather than rolling a new one.
## Retry-this-map is the semantic we want there; "give me a different map" is
## menu → new game, which calls [method start] afresh.
func ensure_started(fallback_seed: int = 0) -> void:
	if is_active():
		return
	var cfg := RunConfig.new()
	cfg.seed = fallback_seed
	start(cfg)


## Drop the live run. Called when leaving a finished run for the menu, so the
## next [method ensure_started] resolves a fresh seed instead of inheriting a
## spent one. Tests call it in `before_each` for the same reason: an autoload
## outlives every test in GUT's single process.
##
## [member outcome] deliberately SURVIVES: a run ends and is routed away from
## in the same breath, so clearing it here would delete the terminal state at
## the exact moment a results screen would want to read it. [method start] is
## what clears it, which is the moment a stale outcome could actually mislead.
## [method is_active] keys off [member config], so a surviving outcome never
## makes a dead run look live.
func end() -> void:
	config = null
	roster = null


func _on_run_ended(run_outcome: RunOutcome) -> void:
	outcome = run_outcome
	run_recorded.emit(run_outcome)
