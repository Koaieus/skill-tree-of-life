extends GutTest

## The SHIPPED board actually scales spell damage through [SqrtFormula]
## (#760, renamed from KneeSqrtFormula in #776), not through the
## [RatioFormula] it used before.
##
## This guard exists because the mis-wire is otherwise easy to miss: at
## small INT the two formulas can read close together, so a spot-check test
## that only ever samples a handful of low values might not notice a silent
## revert to `script_ratio`. Sampling across a wide spread is what tells
## them apart.
##
## Deliberately asserts WIRING and SHAPE only — never the authored `divisor`
## number, which is the owner's to retune post-acceptance (#776).

const BOARD := preload("res://entity/default_entity_board.tres")


func _spell_damage_formula() -> StatFormula:
	var board: StatBoard = BOARD.duplicate(true)
	for m in board.intrinsic_modifiers:
		if m.stat_id == &"spell_damage" and m.formula is SqrtFormula:
			return m.formula
	return null


func test_the_shipped_board_scales_spell_damage_through_sqrt() -> void:
	var f := _spell_damage_formula()
	assert_not_null(f,
			"default_entity_board.tres must carry a SqrtFormula for spell_damage")
	assert_eq((f as SqrtFormula).source_stat_id, &"intelligence",
			"and it must be driven by INT")


func test_the_shipped_wiring_is_sublinear_across_the_sample_points() -> void:
	# Shape, not values: this survives the owner retuning the divisor.
	var f := _spell_damage_formula() as SqrtFormula
	assert_not_null(f, "no SqrtFormula on the board")
	var board: StatBoard = BOARD.duplicate(true)
	board.intelligence.base_value = 1000.0
	var at_lo := f.compute(board)
	board.intelligence.base_value = 2000.0
	var at_hi := f.compute(board)
	assert_gt(at_hi, at_lo, "still strictly increasing")
	assert_lt(at_hi, at_lo * 2.0,
			"doubling INT must NOT double spell damage")
