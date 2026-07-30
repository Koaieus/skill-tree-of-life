extends GutTest

## `core_healing` — an integer, ungated, unramped per-turn heal on the entity
## `health` pool. Acceptance for #277 / D-25.

const _BOARD := preload("res://entity/default_entity_board.tres")

var _board: StatBoard


func before_each() -> void:
	_board = _BOARD.duplicate(true) as StatBoard
	_board.apply_intrinsics()


func test_core_healing_exists_with_placeholder_rate_one() -> void:
	assert_not_null(StatRegistry.get_def(&"core_healing"),
		"core_healing StatDef should be registered")
	assert_not_null(_board.core_healing, "default board should carry core_healing")
	assert_eq(int(_board.core_healing.get_value()), 1,
		"D-25 placeholder is 1/turn — the break-even point against a 1-node chip (#268 measures the real one)")


func test_turn_upkeep_heals_the_health_pool() -> void:
	_board.health.deplete(5.0)
	var before := _board.health.current
	_board.apply_per_turn_upkeep()
	assert_almost_eq(_board.health.current, before + 1.0, 0.001,
		"health should gain core_healing at turn start")


func test_heal_clamps_at_max() -> void:
	_board.health.restore_to_full()
	_board.apply_per_turn_upkeep()
	assert_almost_eq(_board.health.current, float(_board.health.get_value()), 0.001,
		"a full pool must not overflow its cap")


func test_taking_damage_does_not_suppress_the_next_turn_heal() -> void:
	# The pinned no-gate contract (D-25). A D-9-style damage gate here would
	# reward camping — exactly what D-10's forced-dealloc cascade punishes —
	# so damage taken *this* turn must not touch next turn's heal.
	_board.health.deplete(5.0)
	var damaged := _board.health.current
	_board.apply_per_turn_upkeep()
	assert_almost_eq(_board.health.current, damaged + 1.0, 0.001,
		"first heal after damage")

	# Damage again immediately, then take the next upkeep: still the full rate.
	_board.health.deplete(3.0)
	var damaged_again := _board.health.current
	_board.apply_per_turn_upkeep()
	assert_almost_eq(_board.health.current, damaged_again + 1.0, 0.001,
		"damage must never gate core_healing — no gate, no ramp")


func test_heal_does_not_ramp_over_consecutive_undamaged_turns() -> void:
	# The other half of D-25: node regen ramps (D-9), the death clock must not.
	_board.health.deplete(9.0)
	var start := _board.health.current
	for i in 3:
		_board.apply_per_turn_upkeep()
	assert_almost_eq(_board.health.current, start + 3.0, 0.001,
		"three undamaged turns heal 3 x 1, not an escalating amount")


func test_rate_is_an_ordinary_stat_a_class_can_modify() -> void:
	_board.core_healing.base_value = 4.0
	_board.health.deplete(9.0)
	var before := _board.health.current
	_board.apply_per_turn_upkeep()
	assert_almost_eq(_board.health.current, before + 4.0, 0.001,
		"upkeep should read the modified rate")
