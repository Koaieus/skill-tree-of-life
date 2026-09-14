extends GutTest

## #891 (ADR 0016, decisions 1 and 3): a RatioFormula contributes a LINE —
## `value × source / divisor`, no floor — and the INT stat floors the finished
## total once (#890). Display normalises the merged rule to a unit numerator:
## "+1 <stat> per <divisor / value> <SRC>", flipping to "+<value / divisor>
## <stat> per <SRC>" when that step drops below 1.
##
## Boards are hand-built — a bare `EntityStatBoard.new()` with the four stats
## each test needs minted off their registry defs and NO intrinsics — so no
## authored `.tres` value is pinned here.

var _board: EntityStatBoard = null


func before_each() -> void:
	_board = EntityStatBoard.new()
	for id in [&"wisdom", &"strength", &"intelligence", &"xp_per_turn", &"blade_damage"]:
		var s := ScalarStat.new()
		s.definition = StatRegistry.get_def(id)
		s.base_value = 0.0
		_board.set(id, s)


func _ratio(source: StringName, divisor: float) -> RatioFormula:
	var f := RatioFormula.new()
	f.source_stat_id = source
	f.divisor = divisor
	return f


func _ratio_mod(stat_id: StringName, value: float, source: StringName, divisor: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	m.formula = _ratio(source, divisor)
	return m


func _inc(stat_id: StringName, pct: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.INCREASE
	m.value = pct
	return m


func _stat_name(stat_id: StringName) -> String:
	var def: StatDef = StatRegistry.get_def(stat_id)
	return def.modifier_name if not def.modifier_name.is_empty() else def.display_name


# --- 1. compute is the line ---------------------------------------------------

func test_compute_is_source_over_divisor_without_floor() -> void:
	_board.wisdom.base_value = 7.0
	assert_almost_eq(_ratio(&"wisdom", 5.0).compute(_board), 1.4, 1e-9, "7 / 5 = 1.4, not 1")


# --- 2. the INT stat floors the line (needs #890) -----------------------------

func test_unit_ratio_into_int_stat_floors_at_the_stat() -> void:
	_board.xp_per_turn.base_value = 0.0
	_board.add_modifier(_ratio_mod(&"xp_per_turn", 1.0, &"wisdom", 5.0))
	var expected := {13: 2, 15: 3, 20: 4, 21: 4}
	for wis in expected:
		_board.wisdom.base_value = float(wis)
		assert_eq(int(_board.xp_per_turn.value), expected[wis], "WIS %d" % wis)


# --- 3. a merged (fractional) coefficient hands out its point when attained ---

func test_merged_coefficient_contributes_fractionally_and_the_stat_floors() -> void:
	_board.blade_damage.base_value = 0.0
	var m := _ratio_mod(&"blade_damage", 1.5, &"strength", 20.0)
	_board.add_modifier(m)
	_board.strength.base_value = 30.0
	assert_almost_eq(m.get_effective_value(_board), 2.25, 1e-9, "1.5 × 30 / 20")
	assert_eq(int(_board.blade_damage.value), 2, "STR 30 → 2.25 reads 2 (stair read 1)")
	_board.strength.base_value = 40.0
	assert_eq(int(_board.blade_damage.value), 3, "STR 40 → 3")


# --- 4. smooth under % increased ---------------------------------------------

func test_ratio_under_increased_is_a_ramp_not_a_burst() -> void:
	_board.blade_damage.base_value = 0.0
	_board.add_modifier(_ratio_mod(&"blade_damage", 1.0, &"strength", 20.0))
	_board.add_modifier(_inc(&"blade_damage", 200.0))
	var expected := {7: 1, 14: 2, 20: 3}
	for str_v in expected:
		_board.strength.base_value = float(str_v)
		assert_eq(int(_board.blade_damage.value), expected[str_v], "STR %d" % str_v)


# --- 5. format() normalises to a unit numerator ------------------------------

func _xp_format(value: float, divisor: float) -> String:
	return _ratio_mod(&"xp_per_turn", value, &"wisdom", divisor).format()


func test_format_at_unit_value_is_byte_identical_to_today() -> void:
	assert_eq(_xp_format(1.0, 5.0), "+1 %s per 5 WIS" % _stat_name(&"xp_per_turn"))


func test_format_of_a_merged_value_normalises_the_divisor() -> void:
	var name := _stat_name(&"xp_per_turn")
	assert_eq(_xp_format(4.0 / 3.0, 5.0), "+1 %s per 3.75 WIS" % name)
	assert_eq(_xp_format(2.0, 5.0), "+1 %s per 2.5 WIS" % name)


func test_format_flips_to_a_multiple_per_source_when_the_step_drops_below_one() -> void:
	var name := _stat_name(&"xp_per_turn")
	assert_eq(_xp_format(1.0, 0.05), "+20 %s per WIS" % name)
	var m := _ratio_mod(&"xp_per_turn", 40.0, &"intelligence", 10.0)
	assert_eq(m.format(), "+4 %s per INT" % name)


func test_format_at_a_step_of_exactly_one_drops_the_number() -> void:
	assert_eq(_xp_format(5.0, 5.0), "+1 %s per WIS" % _stat_name(&"xp_per_turn"))


# --- 6. other formula shapes render exactly as before --------------------------

func test_threshold_bound_modifier_format_is_unchanged() -> void:
	var f := ThresholdFormula.new()
	f.source_stat_id = &"intelligence"
	f.breakpoints = [50.0, 150.0, 500.0] as Array[float]
	var m := StatModifier.new()
	m.stat_id = &"blade_damage"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 2.0
	m.formula = f
	assert_eq(m.format(), "+2 %s at 50 / 150 / 500 INT" % _stat_name(&"blade_damage"))


func test_expression_bound_modifier_format_is_unchanged() -> void:
	var f := ExpressionFormula.new()
	f.formula = "strength * 2"
	f.inputs = [&"strength"] as Array[StringName]
	f.per_phrase = "twice STR"
	var m := StatModifier.new()
	m.stat_id = &"blade_damage"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 3.0
	m.formula = f
	assert_eq(m.format(), "+3 %s per twice STR" % _stat_name(&"blade_damage"))


# --- 7. the merge key does not move ------------------------------------------

func test_merge_key_of_a_ratio_modifier_is_the_formula_dict_without_value() -> void:
	var m := _ratio_mod(&"xp_per_turn", 1.0, &"wisdom", 5.0)
	var key := StatModifierCodec.merge_key(m)
	assert_false(key.has("value"), "value is erased")
	assert_eq(key["formula"]["type"], StatModifierCodec.TAG_RATIO)
	assert_eq(key["formula"]["divisor"], 5.0)
	assert_eq(String(key["formula"]["source_stat_id"]), "wisdom")
	m.value = 4.0 / 3.0
	assert_eq(StatModifierCodec.merge_key(m), key, "a merged value leaves the key untouched")
