extends GutTest

## Acceptance for #457 — the determinism contract. `GameSession` resolves the
## seed sentinel EXACTLY ONCE, up front, and owns the live run (config, roster,
## outcome). The companion half — "the same resolved seed produces the same
## graph" — lives in `test/unit/test_procgen_determinism.gd`.
##
## `GameSession` is an autoload, so it outlives every test in GUT's single
## process; `before_each`/`after_all` close the run to keep leakage out.


func before_each() -> void:
	GameSession.end()


func after_all() -> void:
	GameSession.end()


func _config(config_seed: int) -> RunConfig:
	var cfg := RunConfig.new()
	cfg.seed = config_seed
	return cfg


func test_no_run_is_live_before_start() -> void:
	assert_false(GameSession.is_active(), "no run before start()")
	assert_null(GameSession.config)


func test_explicit_seed_is_used_as_is() -> void:
	GameSession.start(_config(12345))
	assert_eq(GameSession.config.seed, 12345)


func test_zero_seed_resolves_to_a_concrete_value() -> void:
	GameSession.start(_config(0))
	assert_ne(GameSession.config.seed, 0,
			"seed 0 is the 'randomise me' sentinel and must not survive start()")


## The core of the acceptance: reading the seed back never re-rolls it. If it
## did, the number on the pause-menu footer would not be the number procgen used.
func test_resolution_happens_once() -> void:
	GameSession.start(_config(0))
	var resolved: int = GameSession.config.seed
	for _i in 5:
		assert_eq(GameSession.config.seed, resolved, "re-reading re-randomised the seed")
	GameSession.ensure_started(0)
	assert_eq(GameSession.config.seed, resolved, "ensure_started re-rolled a live run's seed")


func test_zero_seed_resolves_differently_across_runs() -> void:
	# Not a strict guarantee for any single pair of draws, so sample: a
	# resolver that returned a constant would make every one of these equal.
	var seeds := {}
	for _i in 8:
		GameSession.end()
		GameSession.start(_config(0))
		seeds[GameSession.config.seed] = true
	assert_gt(seeds.size(), 1, "seed 0 resolved to the same value 8 times running")


func test_resolve_seed_is_idempotent() -> void:
	assert_eq(RunConfig.resolve_seed(99), 99)
	assert_eq(RunConfig.resolve_seed(RunConfig.resolve_seed(99)), 99)
	assert_ne(RunConfig.resolve_seed(0), 0)


func test_ensure_started_opens_a_run_from_a_fallback_seed() -> void:
	GameSession.ensure_started(777)
	assert_true(GameSession.is_active())
	assert_eq(GameSession.config.seed, 777,
			"a directly-launched level's authored preset seed should seed the session")


func test_ensure_started_leaves_a_live_run_alone() -> void:
	GameSession.start(_config(4242))
	GameSession.ensure_started(1)
	assert_eq(GameSession.config.seed, 4242,
			"a live run must win over a level's authored fallback")


## The documented consequence of that: the pause menu's restart reloads the
## scene without ending the run, so the retry is the SAME map.
func test_a_scene_reload_replays_the_same_map() -> void:
	GameSession.start(_config(0))
	var resolved: int = GameSession.config.seed
	# What a level's `_setup_level` does on the reload — no start(), just this.
	GameSession.ensure_started(0)
	assert_eq(GameSession.config.seed, resolved)


func test_end_lets_the_next_run_resolve_fresh() -> void:
	GameSession.start(_config(4242))
	GameSession.end()
	assert_false(GameSession.is_active())
	assert_null(GameSession.config)
	GameSession.ensure_started(9)
	assert_eq(GameSession.config.seed, 9)


func test_start_opens_an_empty_roster_and_clears_the_previous_outcome() -> void:
	GameSession.start(_config(1))
	GameSession.outcome = RunOutcome.new()
	assert_not_null(GameSession.roster)
	GameSession.start(_config(2))
	assert_null(GameSession.outcome, "a new run inherited the previous run's outcome")
	assert_eq(GameSession.roster.all().size(), 0)


func test_the_run_outcome_is_recorded_off_the_bus() -> void:
	GameSession.start(_config(1))
	var outcome := RunOutcome.new()
	outcome.turn_count = 17
	Events.run_ended.emit(outcome)
	assert_eq(GameSession.outcome, outcome, "GameSession did not record the run's outcome")
	assert_eq(GameSession.outcome.turn_count, 17)


## A run ends and is routed away from in the same breath (`GameRoot`'s run-end
## route calls `end()`), so `end()` must not delete the terminal state at the
## moment a results screen would read it. `start()` is what clears it.
func test_the_outcome_survives_end_and_is_cleared_by_the_next_start() -> void:
	GameSession.start(_config(1))
	var outcome := RunOutcome.new()
	Events.run_ended.emit(outcome)
	GameSession.end()
	assert_eq(GameSession.outcome, outcome, "end() deleted the run's recorded outcome")
	assert_false(GameSession.is_active(), "a recorded outcome must not make a dead run look live")
	GameSession.start(_config(2))
	assert_null(GameSession.outcome)


func test_run_started_signal_carries_the_resolved_config() -> void:
	watch_signals(GameSession)
	GameSession.start(_config(0))
	assert_signal_emitted(GameSession, "run_started")
	var params: Array = get_signal_parameters(GameSession, "run_started", 0)
	var emitted: RunConfig = params[0]
	assert_eq(emitted, GameSession.config)
	assert_ne(emitted.seed, 0, "run_started fired before the seed was resolved")
