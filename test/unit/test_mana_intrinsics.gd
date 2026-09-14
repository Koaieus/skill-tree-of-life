extends GutTest

## #766 — mana and mana regen never bound: infinite mana still bought exactly
## two spells, because Action Points gate casting within a turn and mana never
## caught up as a cross-turn gate once INT (the intended runaway stat, #760)
## passed a couple hundred. Owner call, 2026-09-14: the INT->mana / INT->
## mana_per_turn intrinsics stay, but go "very conservative" — the BOARD
## (procgen-rolled `mana +` / `mana_per_turn +` grants, `procgen/pools/
## intelligence.tres`) is the real mana source now; the innate is a rounding
## error.
##
## Two things pinned here, deliberately loose on the exact numbers (owner
## tunes, agents test — `.claude/rules/stat-knobs-and-bins.md`):
##   1. Shape + monotonicity + token-sized bounds of both intrinsics: reads
##      the SHIPPED boards as input (same `_mod_for` pattern as
##      `test_threshold_formula.gd`'s `_shipped()`), but asserts only shape
##      (RatioFormula/ThresholdFormula off intelligence), monotonicity, and
##      generous bounds — never the divisor or ladder as a literal.
##   2. Parity: all four boards (default + three blockers) carry
##      byte-identical mana intrinsic formula dicts, the #775 merge premise.

const _BOARDS := {
	"default": preload("res://entity/default_entity_board.tres"),
	"blocker_small": preload("res://entity/blocker/blocker_small_board.tres"),
	"blocker_medium": preload("res://entity/blocker/blocker_medium_board.tres"),
	"blocker_large": preload("res://entity/blocker/blocker_large_board.tres"),
}

var _board: EntityStatBoard = null


func before_each() -> void:
	_board = _BOARDS["default"].duplicate(true)


func _mod_for(board: EntityStatBoard, stat_id: StringName) -> StatModifier:
	for leaf in StatModifier.flatten_all(board.intrinsic_modifiers):
		if leaf.stat_id == stat_id:
			return leaf
	return null


# --- 1. Shape, monotonicity, sublinearity — no divisor/ladder pinned --------

func test_max_mana_intrinsic_is_a_ratio_formula_off_intelligence() -> void:
	var mod := _mod_for(_board, &"mana")
	assert_not_null(mod, "default board grants mana via an intrinsic modifier")
	assert_true(mod.formula is RatioFormula,
		"#766: the max-mana intrinsic is a RatioFormula (floor(INT / divisor))")
	assert_eq((mod.formula as RatioFormula).source_stat_id, &"intelligence")


func test_mana_per_turn_intrinsic_is_a_threshold_formula_off_intelligence() -> void:
	var mod := _mod_for(_board, &"mana_per_turn")
	assert_not_null(mod, "default board grants mana_per_turn via an intrinsic modifier")
	assert_true(mod.formula is ThresholdFormula,
		"#766: the mana-regen intrinsic is a decade ThresholdFormula")
	assert_eq((mod.formula as ThresholdFormula).source_stat_id, &"intelligence")


func test_max_mana_intrinsic_is_zero_at_zero_intelligence() -> void:
	var f := (_mod_for(_board, &"mana").formula as RatioFormula)
	_board.intelligence.base_value = 0.0
	assert_eq(f.compute(_board), 0.0)


func test_mana_per_turn_intrinsic_is_zero_at_zero_intelligence() -> void:
	var f := (_mod_for(_board, &"mana_per_turn").formula as ThresholdFormula)
	_board.intelligence.base_value = 0.0
	assert_eq(f.compute(_board), 0.0)


func test_max_mana_intrinsic_is_monotonically_non_decreasing_in_intelligence() -> void:
	var f := (_mod_for(_board, &"mana").formula as RatioFormula)
	var samples := [0.0, 1000.0, 10000.0, 20000.0]
	var prev := -1.0
	for int_value in samples:
		_board.intelligence.base_value = int_value
		var v := f.compute(_board)
		assert_true(v >= prev, "INT %s -> %s must not drop below the prior sample" % [int_value, v])
		prev = v


func test_mana_per_turn_intrinsic_is_monotonically_non_decreasing_in_intelligence() -> void:
	var f := (_mod_for(_board, &"mana_per_turn").formula as ThresholdFormula)
	var samples := [0.0, 1000.0, 10000.0, 100000.0, 1000000.0]
	var prev := -1.0
	for int_value in samples:
		_board.intelligence.base_value = int_value
		var v := f.compute(_board)
		assert_true(v >= prev, "INT %s -> %s must not drop below the prior sample" % [int_value, v])
		prev = v


func test_max_mana_intrinsic_is_sublinear_at_the_int_ceiling() -> void:
	# #760's intended INT ceiling is 20k. "Very conservative" means the
	# innate's contribution at that ceiling stays a rounding error next to
	# the base pool (10) and rolled `mana +` grants — generously bounded well
	# under the ceiling itself, without pinning the owner's chosen divisor.
	var f := (_mod_for(_board, &"mana").formula as RatioFormula)
	_board.intelligence.base_value = 20000.0
	assert_lt(f.compute(_board), 100.0,
		"the innate max-mana contribution at the INT ceiling must stay token-sized")


func test_mana_per_turn_intrinsic_is_sublinear_at_the_int_ceiling() -> void:
	var f := (_mod_for(_board, &"mana_per_turn").formula as ThresholdFormula)
	_board.intelligence.base_value = 20000.0
	assert_lt(f.compute(_board), 10.0,
		"the innate regen contribution at the INT ceiling must stay token-sized")


# --- 2. Parity across all four boards (#775 merge premise) ------------------

func test_all_four_boards_carry_byte_identical_mana_intrinsic_formulas() -> void:
	var reference: Dictionary = {}
	for stat_id in [&"mana", &"mana_per_turn"]:
		var mod := _mod_for(_BOARDS["default"], stat_id)
		assert_not_null(mod, "default board carries a %s intrinsic" % stat_id)
		reference[stat_id] = mod.formula.to_dict()

	for board_name in _BOARDS:
		if board_name == "default":
			continue
		for stat_id in [&"mana", &"mana_per_turn"]:
			var mod := _mod_for(_BOARDS[board_name], stat_id)
			assert_not_null(mod, "%s board carries a %s intrinsic" % [board_name, stat_id])
			assert_eq(mod.formula.to_dict(), reference[stat_id],
				"%s's %s intrinsic formula must match default_entity_board's byte-for-byte" % [board_name, stat_id])
