extends GutTest

## #890 (ADR 0016, decision 2): an INT-typed scalar stat FLOORS its finished
## total — truncation toward zero — instead of rounding to nearest. This is the
## only rounding in the pipeline and it is the stat's, applied once, after the
## bins. FLOAT stats and a pool's own `current` rounding are untouched.


func _int_stat(base: float) -> ScalarStat:
	var d := StatDef.new()
	d.id = &"test_int"
	d.value_type = StatDef.ValueType.INT
	var s := ScalarStat.new()
	s.definition = d
	s.base_value = base
	return s


func _float_stat(base: float) -> ScalarStat:
	var d := StatDef.new()
	d.id = &"test_float"
	d.value_type = StatDef.ValueType.FLOAT
	var s := ScalarStat.new()
	s.definition = d
	s.base_value = base
	return s


func _mod(stat_id: StringName, op: int, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op as StatModifier.Operation
	m.value = value
	return m


func _int_with_add(add: float) -> ScalarStat:
	var s := _int_stat(0.0)
	s.add_modifier(_mod(&"test_int", StatModifier.Operation.ADD_BASE, add))
	return s


# --- Acceptance 1: INT floors once, toward zero ------------------------------

func test_int_stat_with_five_percent_increased_floors_to_base() -> void:
	# 10 × 1.05 = 10.5 — used to round up to 11.
	var s := _int_stat(10.0)
	s.add_modifier(_mod(&"test_int", StatModifier.Operation.INCREASE, 5.0))
	assert_eq(s.get_value(), 10, "10.5 must floor to 10, not round to 11")


func test_int_stat_fractional_total_below_one_reads_zero() -> void:
	assert_eq(_int_with_add(0.9).get_value(), 0, "0.9 must truncate to 0")


func test_int_stat_negative_fraction_above_minus_one_reads_zero() -> void:
	assert_eq(_int_with_add(-0.9).get_value(), 0, "-0.9 must truncate toward zero to 0")


func test_int_stat_two_point_six_reads_two() -> void:
	assert_eq(_int_with_add(2.6).get_value(), 2, "2.6 must truncate to 2")


func test_int_stat_minus_two_point_six_reads_minus_two() -> void:
	assert_eq(_int_with_add(-2.6).get_value(), -2, "-2.6 must truncate toward zero to -2")


func test_int_stat_value_is_a_real_int() -> void:
	assert_eq(typeof(_int_with_add(2.6).get_value()), TYPE_INT)


# --- Acceptance 2: FLOAT unchanged -------------------------------------------

func test_float_stat_keeps_its_fraction() -> void:
	var s := _float_stat(10.0)
	s.add_modifier(_mod(&"test_float", StatModifier.Operation.INCREASE, 5.0))
	assert_almost_eq(float(s.get_value()), 10.5, 0.0001, "a FLOAT stat is not coerced")


# --- Acceptance 3: a pool's own `current` rounding is untouched --------------

func test_pool_available_still_rounds_current_to_nearest() -> void:
	var d := PoolStatDef.new()
	d.id = &"test_pool"
	var p := PoolStat.new()
	p.definition = d
	p.base_value = 10.0
	p.current = 2.6
	assert_eq(p.available(), 3, "PoolStat.available() keeps roundi(current)")


# --- #895: a merged (node-local) read floors the same as a bare one ----------

func _overlay(op: int, value: float) -> ModifierBins:
	# A stand-in for a node board's bins for the same id.
	var s := _int_stat(0.0)
	s.add_modifier(_mod(&"test_int", op, value))
	return s.bins


func test_merged_int_read_floors_the_finished_total() -> void:
	var s := _int_stat(1.0)
	var overlays: Array[ModifierBins] = [_overlay(StatModifier.Operation.ADD_BASE, 0.5)]
	assert_eq(s.get_value_with(overlays), 1, "1 + 0.5 from a node-local line must floor to 1")


func test_merged_int_read_is_a_real_int() -> void:
	var s := _int_stat(1.0)
	var overlays: Array[ModifierBins] = [_overlay(StatModifier.Operation.ADD_BASE, 7.0)]
	assert_eq(typeof(s.get_value_with(overlays)), TYPE_INT)
	assert_eq(s.get_value_with(overlays), 8)


func test_merged_float_read_keeps_its_fraction() -> void:
	var s := _float_stat(1.0)
	var o := _float_stat(0.0)
	o.add_modifier(_mod(&"test_float", StatModifier.Operation.ADD_BASE, 0.5))
	var overlays: Array[ModifierBins] = [o.bins]
	assert_almost_eq(float(s.get_value_with(overlays)), 1.5, 0.0001)
