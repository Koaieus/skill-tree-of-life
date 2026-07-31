extends GutTest

## #289 — a formula-bound modifier describes its own rule in ONE short line,
## and the number it shows is the number it divides by.
##
## Two halves:
##   1. RatioFormula computes exactly what the ExpressionFormulas it replaced
##      computed (characterization — the migration must be behaviour-neutral).
##   2. Every formula reachable from the shipped boards yields a non-empty
##      "per" phrase, so a future formula can't ship undescribed.

const BOARD := preload("res://entity/default_entity_board.tres")
const BALANCED_CORE := preload("res://entity/core/balanced_core.tres")
const LEVEL_SCALING := preload("res://stats_system/formulas/level_scaling.tres")

var _board: StatBoard = null


func before_each() -> void:
	_board = BOARD.duplicate(true)


func _ratio(source: StringName, divisor: float) -> RatioFormula:
	var f := RatioFormula.new()
	f.source_stat_id = source
	f.divisor = divisor
	return f


func _expr(text: String, inputs: Array[StringName]) -> ExpressionFormula:
	var f := ExpressionFormula.new()
	f.formula = text
	f.inputs = inputs
	return f


# --- 1. Characterization: RatioFormula == the expression it replaced ---------

func test_ratio_matches_replaced_expression_across_the_range() -> void:
	# The six migrated intrinsics, as (source, divisor, old expression).
	var cases := [
		[&"intelligence", 10.0, "floor(float(intelligence) / 10.0)"],
		[&"wisdom", 2.0, "floor(float(wisdom) / 2.0)"],
		[&"dexterity", 10.0, "floor(float(dexterity) / 10.0)"],
		[&"strength", 10.0, "floor(float(strength) / 10.0)"],
		[&"strength", 20.0, "floor(strength / 20.)"],
	]
	for case in cases:
		var source: StringName = case[0]
		var ratio := _ratio(source, case[1])
		var old := _expr(case[2], [source] as Array[StringName])
		var stat := _board.get_stat(source)
		assert_not_null(stat, "board carries %s" % source)
		for v in [0, 1, 9, 10, 19, 20, 21, 55, 100]:
			stat.base_value = float(v)
			assert_eq(
				ratio.compute(_board), old.compute(_board),
				"%s=%d under /%s" % [source, v, case[1]]
			)


func test_zero_divisor_returns_zero_and_errors() -> void:
	var f := _ratio(&"strength", 0.0)
	_board.strength.base_value = 50.0
	assert_eq(f.compute(_board), 0.0)
	assert_push_error("RatioFormula: divisor is 0 for source 'strength'")


func test_missing_source_stat_returns_zero() -> void:
	assert_eq(_ratio(&"not_a_stat", 10.0).compute(_board), 0.0)


# --- 2. Generated "per" phrases ----------------------------------------------

func test_ratio_phrase_is_divisor_plus_abbreviation() -> void:
	assert_eq(_ratio(&"strength", 20.0).describe_per(), "20 STR")
	assert_eq(_ratio(&"wisdom", 2.0).describe_per(), "2 WIS")


func test_ratio_phrase_drops_a_divisor_of_one() -> void:
	assert_eq(_ratio(&"perception", 1.0).describe_per(), "PER")


func test_linear_phrase_is_the_bare_abbreviation() -> void:
	var f := LinearFormula.new()
	f.source_stat_id = &"perception"
	assert_eq(f.describe_per(), "PER")


func test_authored_phrase_overrides_the_generated_one() -> void:
	var f := _ratio(&"strength", 20.0)
	f.per_phrase = "swing"
	assert_eq(f.describe_per(), "swing")


func test_expression_phrase_is_authored_only() -> void:
	# Never derived from the expression text — #289 forbids parsing it back.
	assert_eq(_expr("floor(strength / 3.0)", [&"strength"] as Array[StringName]).describe_per(), "")


# --- 3. Every shipped formula is described -----------------------------------

func _assert_all_described(mods: Array, where: String) -> void:
	for leaf in StatModifier.flatten_all(mods):
		if leaf.formula == null:
			continue
		assert_ne(
			leaf.formula.describe_per(), "",
			"%s: modifier on '%s' has an undescribed formula" % [where, leaf.stat_id]
		)


func test_every_board_intrinsic_formula_is_described() -> void:
	_assert_all_described(BOARD.intrinsic_modifiers, "default_entity_board")


func test_every_balanced_core_formula_is_described() -> void:
	_assert_all_described(BALANCED_CORE.modifiers, "balanced_core")


func test_shared_level_curve_is_described() -> void:
	# "level", not "level after the 1st" — the -1 is the formula's zero point, not
	# something a player thinks about; they read the curve as "level up -> +stats".
	assert_eq(LEVEL_SCALING.describe_per(), "level")


# --- 4. The composed sentence -------------------------------------------------

func test_format_appends_the_per_clause_with_the_coefficient() -> void:
	var m := StatModifier.new()
	m.stat_id = &"blade_size"
	m.value = 1.0
	m.formula = _ratio(&"strength", 20.0)
	# Coefficient, not effective value — the clause carries the variable part.
	assert_eq(m.format(), "+1 Blade Size per 20 STR")


func test_format_keeps_the_coefficient_when_bound_to_a_board() -> void:
	_board.strength.base_value = 60.0
	var m := StatModifier.new()
	m.stat_id = &"blade_size"
	m.value = 1.0
	m.formula = _ratio(&"strength", 20.0)
	m.bind(_board)
	assert_eq(m.get_effective_value(), 3.0, "still computes live")
	assert_eq(m.format(), "+1 Blade Size per 20 STR", "sentence stays the rule")


func test_format_of_an_undescribed_formula_omits_the_clause() -> void:
	var m := StatModifier.new()
	m.stat_id = &"blade_size"
	m.value = 2.0
	m.formula = _expr("strength * 2", [&"strength"] as Array[StringName])
	assert_eq(m.format(), "+2 Blade Size", "no dangling 'per'")


func test_static_modifier_sentence_is_untouched() -> void:
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.value = 4.0
	assert_eq(m.format(), "+4 Strength")
