extends GutTest

## The SHIPPED board actually scales spell damage through [KneeSqrtFormula]
## (#760), not through the [RatioFormula] it used before.
##
## This guard exists because the mis-wire is otherwise INVISIBLE: below the
## knee the two formulas are byte-identical by construction, so every existing
## spell-damage test stays green if `default_entity_board.tres` is silently
## reverted to `script_ratio`. Only a sample ABOVE the knee can tell them
## apart, and nothing else in the suite takes one.
##
## Deliberately asserts WIRING and SHAPE only — never the authored `knee` or
## `divisor` numbers, which are the owner's to retune post-acceptance (#760).

const BOARD := preload("res://entity/default_entity_board.tres")


func _spell_damage_formula() -> StatFormula:
	var board: StatBoard = BOARD.duplicate(true)
	for m in board.intrinsic_modifiers:
		if m.stat_id == &"spell_damage" and m.formula is KneeSqrtFormula:
			return m.formula
	return null


func test_the_shipped_board_scales_spell_damage_through_knee_sqrt() -> void:
	var f := _spell_damage_formula()
	assert_not_null(f,
			"default_entity_board.tres must carry a KneeSqrtFormula for spell_damage")
	assert_eq((f as KneeSqrtFormula).source_stat_id, &"intelligence",
			"and it must be driven by INT")


func test_the_shipped_wiring_is_actually_sublinear_far_above_its_own_knee() -> void:
	# Shape, not values: read whatever knee the board currently authors and
	# probe well past it, so this survives the owner retuning that number.
	var f := _spell_damage_formula() as KneeSqrtFormula
	assert_not_null(f, "no KneeSqrtFormula on the board")
	var board: StatBoard = BOARD.duplicate(true)
	var lo := f.knee * 4.0
	board.intelligence.base_value = lo
	var at_lo := f.compute(board)
	board.intelligence.base_value = lo * 2.0
	var at_hi := f.compute(board)
	assert_gt(at_hi, at_lo, "still strictly increasing above the knee")
	assert_lt(at_hi, at_lo * 2.0,
			"doubling INT far above the knee must NOT double spell damage")
