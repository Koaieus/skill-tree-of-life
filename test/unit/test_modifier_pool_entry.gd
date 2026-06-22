extends GutTest

## Verifies ModifierPoolEntry.roll() mints fresh StatModifiers, samples
## value_range correctly, coerces to the target stat's value_type (so an INT
## stat snaps; a FLOAT stat doesn't), and that ModifierPool.roll() draws
## until budget is exhausted.


func _entry(stat_id: StringName, op: int, lo: float, hi: float, cost: int = 1, weight: float = 1.0) -> ModifierPoolEntry:
	var e := ModifierPoolEntry.new()
	e.id = StringName("test_" + str(stat_id))
	e.stat_id = stat_id
	e.operation = op
	e.value_range = Vector2(lo, hi)
	e.cost = cost
	e.weight = weight
	return e


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_roll_mints_fresh_modifier() -> void:
	var e := _entry(&"strength", StatModifier.Operation.ADD_BASE, 5.0, 5.0)
	var m1 := e.roll(_rng())
	var m2 := e.roll(_rng(2))
	assert_not_null(m1)
	assert_ne(m1, m2, "roll() must mint fresh instances per call")
	assert_eq(m1.stat_id, &"strength")
	assert_eq(m1.operation, StatModifier.Operation.ADD_BASE)


func test_value_range_sampling_within_bounds() -> void:
	var e := _entry(&"strength", StatModifier.Operation.ADD_BASE, 5.0, 8.0)
	var rng := _rng(42)
	for i in 50:
		var m := e.roll(rng)
		# strength is INT-typed → values round to integers in [5, 8].
		assert_true(m.value >= 5.0 and m.value <= 8.0, "value %s out of [5,8]" % m.value)


func test_int_stat_coerces_to_whole_numbers() -> void:
	var e := _entry(&"strength", StatModifier.Operation.ADD_BASE, 1.0, 4.0)
	var rng := _rng(7)
	for i in 20:
		var m := e.roll(rng)
		assert_eq(m.value, float(int(m.value)), "strength is INT — rolled value %s must be whole" % m.value)


func test_int_stat_multiply_does_not_coerce_to_one() -> void:
	# Regression: ×1.07 INT was rounding to ×1.0, destroying the multiply roll.
	# Only ADD_BASE/ADD_BONUS flow through value_type; INCREASE/MULTIPLY are
	# raw scalars.
	var e := _entry(&"intelligence", StatModifier.Operation.MULTIPLY, 1.05, 1.15)
	var rng := _rng(42)
	for i in 30:
		var m := e.roll(rng)
		assert_true(m.value >= 1.05 and m.value <= 1.15, "INT MULTIPLY value %s clamped wrongly" % m.value)
		assert_ne(m.value, 1.0, "INT MULTIPLY should NOT collapse to 1.0")


func test_increase_snaps_to_int() -> void:
	# INCREASE is percent-points and reads as integers in UI (+13%, not +12.5%).
	# We snap to int regardless of the target stat's value_type. (Replaces the
	# old "does_not_coerce" — design changed to always-snap-INCREASE.)
	var e := _entry(&"intelligence", StatModifier.Operation.INCREASE, 12.5, 12.5)
	var m := e.roll(_rng(7))
	assert_eq(m.value, 13.0, "12.5 should snap to 13 (round-half-up)")
	# Negative INCREASE also snaps.
	var e_neg := _entry(&"intelligence", StatModifier.Operation.INCREASE, -3.7, -3.7)
	var m_neg := e_neg.roll(_rng(7))
	assert_eq(m_neg.value, -4.0, "-3.7 should snap to -4")


func test_unknown_stat_does_not_coerce() -> void:
	# If StatRegistry has no def for the id, roll() should pass the raw float.
	var e := _entry(&"definitely_not_a_stat", StatModifier.Operation.ADD_BASE, 1.5, 1.5)
	var m := e.roll(_rng())
	assert_almost_eq(m.value, 1.5, 0.0001)


func test_pool_roll_until_budget_exhausted() -> void:
	var pool := ModifierPool.new()
	pool.entries = [_entry(&"strength", StatModifier.Operation.ADD_BASE, 1.0, 1.0, 1, 10.0)]
	var rolled := pool.roll(5, _rng(1))
	assert_eq(rolled.size(), 5, "budget 5 / cost 1 should yield 5 picks")


func test_pool_roll_stops_when_nothing_affordable() -> void:
	var pool := ModifierPool.new()
	pool.entries = [_entry(&"strength", StatModifier.Operation.ADD_BASE, 1.0, 1.0, 3, 10.0)]
	var rolled := pool.roll(2, _rng(1))
	assert_eq(rolled.size(), 0, "budget 2 < cost 3 → no picks")


func test_pool_roll_empty_pool() -> void:
	var pool := ModifierPool.new()
	var rolled := pool.roll(10, _rng(1))
	assert_eq(rolled.size(), 0)
