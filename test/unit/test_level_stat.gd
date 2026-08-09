extends GutTest

## #200 — `level` as a plain ScalarStat on the board, so level-scaling formula
## modifiers can bind to it and auto-recalculate. The design rejects a bespoke
## `DerivedStat` class + `fill_count` on PoolStat: a plain ScalarStat whose
## base_value the level-up handler writes already gives reactive recalc for free
## (base_value's setter emits value_changed → bound formula modifiers recompute),
## and keeps level moddable like every other stat.

const _BOARD := preload("res://entity/default_entity_board.tres")


func _board() -> EntityStatBoard:
	return _BOARD.duplicate(true) as EntityStatBoard


func test_default_board_carries_level_stat_at_1() -> void:
	var board := _board()
	assert_not_null(board.level, "default board wires a `level` ScalarStat")
	assert_eq(board.get_stat(&"level"), board.level, "get_stat resolves by id (Object.get)")
	assert_eq(int(board.level.value), 1, "starts at level 1")


func test_level_bound_formula_modifier_recalculates_on_level_up() -> void:
	var board := _board()
	# The #194 shape: +level × 1 STR, formula source = level.
	var lin := LinearFormula.new()
	lin.source_stat_id = &"level"
	var mod := StatModifier.new()
	mod.stat_id = &"strength"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = 1.0
	mod.formula = lin
	board.add_modifier(mod.duplicate(true))

	var str_at_1: int = board.strength.value
	board.level.base_value += 1  # simulate one level-up
	assert_eq(int(board.strength.value), str_at_1 + 1, "STR follows level via the bound formula")
	board.level.base_value += 3
	assert_eq(int(board.strength.value), str_at_1 + 4, "recalc stays exact across multiple bumps")


func test_level_stays_moddable_like_any_scalar() -> void:
	var board := _board()
	var m := StatModifier.new()
	m.stat_id = &"level"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 2.0
	board.add_modifier(m)
	assert_eq(int(board.level.value), 3, "a +2 modifier lifts effective level (no read-only special-casing)")
