extends GutTest
## StatModifierAggregator: the per-(stat_id, operation) fuse the v4 draw spends
## into. The precondition merge_into asserts (same stat, same op) is tested
## one level up, through append, the only production path that reaches it:
## a GDScript assert is uncatchable in GUT and stripped in release.

const _ADD := StatModifier.Operation.ADD_BASE
const _MUL := StatModifier.Operation.MULTIPLY
## Deliberately not the content default: the asserts read the floor passed in.
const _FLOOR := 0.3


func _mod(stat: StringName, op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat
	m.operation = op
	m.value = value
	return m


func _entry(stat: StringName, op: StatModifier.Operation, lo: float, hi: float, id: StringName = &"") -> ModifierPoolEntry:
	var e := ModifierPoolEntry.new()
	e.id = id
	e.stat_id = stat
	e.operation = op
	e.value_range = Vector2(lo, hi)
	return e


func test_same_stat_and_op_fuse_into_one() -> void:
	var agg := StatModifierAggregator.new(_FLOOR)
	agg.append(_mod(&"armor", _ADD, 2.0), 1, _entry(&"armor", _ADD, 1, 3))
	agg.append(_mod(&"armor", _ADD, 3.0), 2, _entry(&"armor", _ADD, 1, 3))
	var out := agg.get_aggregate()
	assert_eq(out.size(), 1, "one (stat, op) → one line")
	assert_almost_eq(out[0].value, 5.0, 1e-6, "ADD_BASE fuses by sum")


func test_same_stat_different_op_stays_apart() -> void:
	var agg := StatModifierAggregator.new(_FLOOR)
	agg.append(_mod(&"armor", _ADD, 2.0), 1, _entry(&"armor", _ADD, 1, 3))
	agg.append(_mod(&"armor", StatModifier.Operation.INCREASE, 5.0), 1,
		_entry(&"armor", StatModifier.Operation.INCREASE, 1, 3))
	assert_eq(agg.get_aggregate().size(), 2, "a different operation is never fused")


func test_different_stat_same_op_stays_apart() -> void:
	var agg := StatModifierAggregator.new(_FLOOR)
	agg.append(_mod(&"armor", _ADD, 2.0), 1, _entry(&"armor", _ADD, 1, 3))
	agg.append(_mod(&"mana", _ADD, 2.0), 1, _entry(&"mana", _ADD, 1, 3))
	assert_eq(agg.get_aggregate().size(), 2, "a different stat is never fused")


func test_merge_into_semantics() -> void:
	for op: StatModifier.Operation in [_ADD, StatModifier.Operation.ADD_BONUS, StatModifier.Operation.INCREASE]:
		var a := StatModifierAggregator.merge_into(_mod(&"armor", op, 4.0), _mod(&"armor", op, 3.0))
		assert_almost_eq(a.value, 7.0, 1e-6, "op %d sums" % op)
	var m := StatModifierAggregator.merge_into(_mod(&"armor", _MUL, 1.15), _mod(&"armor", _MUL, 1.15))
	assert_almost_eq(m.value, 1.30, 1e-6, "MULTIPLY fuses by delta sum (×1.30, not ×1.3225)")


func test_multiply_fuses_by_delta_sum() -> void:
	var small := StatModifierAggregator.merge_into(_mod(&"armor", _MUL, 1.02), _mod(&"armor", _MUL, 1.03))
	assert_almost_eq(small.value, 1.05, 1e-6, "1 + Σ(mᵢ − 1): 1.02 & 1.03 → 1.05")
	var big := StatModifierAggregator.merge_into(_mod(&"armor", _MUL, 1.5), _mod(&"armor", _MUL, 1.5))
	assert_almost_eq(big.value, 2.0, 1e-6, "1.5 & 1.5 → 2.0, not 2.25")


func test_fused_multiply_clamps_at_the_floor() -> void:
	var agg := StatModifierAggregator.new(_FLOOR)
	agg.append(_mod(&"armor", _MUL, 0.5), 1, _entry(&"armor", _MUL, 0.5, 0.5))
	agg.append(_mod(&"armor", _MUL, 0.5), 1, _entry(&"armor", _MUL, 0.5, 0.5))
	assert_almost_eq(agg.get_aggregate()[0].value, _FLOOR, 1e-6, "0.5 & 0.5 → 0.0 clamps to the floor")


func test_floor_clamps_the_fused_total_once_not_each_merge() -> void:
	# Pairwise clamping would read clamp(0.0) + 0.5 = floor + 0.5; the fuse
	# clamps only the whole delta sum, which never reached below the floor.
	var agg := StatModifierAggregator.new(_FLOOR)
	for v: float in [0.5, 0.5, 1.5]:
		agg.append(_mod(&"armor", _MUL, v), 1, _entry(&"armor", _MUL, v, v))
	assert_almost_eq(agg.get_aggregate()[0].value, 0.5, 1e-6, "1 + (−0.5 − 0.5 + 0.5)")


func test_reroll_into_clamps_at_the_floor() -> void:
	var group: Array[ModifierPoolEntry] = [
		_entry(&"armor", _MUL, 0.5, 0.5),
		_entry(&"armor", _MUL, 0.5, 0.5),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var mod := _mod(&"armor", _MUL, 1.0)
	StatModifierAggregator.reroll_into(mod, group, rng, _FLOOR)
	assert_almost_eq(mod.value, _FLOOR, 1e-6, "the re-rolled fuse clamps like the draw's")


func test_two_set_modifiers_on_one_stat_share_a_key() -> void:
	# merge_into has no SET branch (it asserts). No authored pool uses SET, so
	# it is unreachable today; pinned here so the day a SET pool is authored
	# the loud failure is a known one: two SETs on one stat WOULD fuse.
	var a := _mod(&"armor", StatModifier.Operation.SET, 1.0)
	var b := _mod(&"armor", StatModifier.Operation.SET, 2.0)
	assert_eq(StatModifierAggregator.key_of(a), StatModifierAggregator.key_of(b))
	assert_ne(StatModifierAggregator.key_of(a),
		StatModifierAggregator.key_of(_mod(&"armor", _ADD, 1.0)))


func test_entries_for_keeps_append_order() -> void:
	# #629's re-roll replays these in this order — a cross-peer determinism pin.
	var agg := StatModifierAggregator.new(_FLOOR)
	var e1 := _entry(&"armor", _ADD, 1, 3, &"e1")
	var e2 := _entry(&"armor", _ADD, 1, 3, &"e2")
	var e3 := _entry(&"armor", _ADD, 1, 3, &"e3")
	agg.append(_mod(&"armor", _ADD, 1.0), 1, e1)
	agg.append(_mod(&"armor", _ADD, 1.0), 1, e2)
	agg.append(_mod(&"armor", _ADD, 1.0), 1, e3)
	var mod: StatModifier = agg.get_aggregate()[0]
	assert_eq(agg.entries_for(mod), [e1, e2, e3] as Array[ModifierPoolEntry])


func test_aggregate_orders_by_descending_total_cost() -> void:
	# armor's total (1+1+2 = 4) beats mana (3) only if costs are SUMMED — its
	# first (1) or last (2) contribution alone would lose.
	var agg := StatModifierAggregator.new(_FLOOR)
	agg.append(_mod(&"armor", _ADD, 1.0), 1, _entry(&"armor", _ADD, 1, 3))
	agg.append(_mod(&"mana", _ADD, 1.0), 3, _entry(&"mana", _ADD, 1, 3))
	agg.append(_mod(&"armor", _ADD, 1.0), 1, _entry(&"armor", _ADD, 1, 3))
	agg.append(_mod(&"sensor_range", _ADD, 1.0), 2, _entry(&"sensor_range", _ADD, 1, 3))
	agg.append(_mod(&"armor", _ADD, 1.0), 2, _entry(&"armor", _ADD, 1, 3))
	var ids: Array[StringName] = []
	for m in agg.get_aggregate():
		ids.append(m.stat_id)
	assert_eq(ids, [&"armor", &"mana", &"sensor_range"] as Array[StringName])


func test_reroll_into_is_seed_deterministic() -> void:
	var group: Array[ModifierPoolEntry] = [
		_entry(&"vision_range", StatModifier.Operation.MULTIPLY, 1.05, 1.3),
		_entry(&"vision_range", StatModifier.Operation.MULTIPLY, 1.1, 1.5),
		_entry(&"vision_range", StatModifier.Operation.MULTIPLY, 1.0, 2.0),
	]
	var values: Array[float] = []
	for i in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9001
		var mod := _mod(&"vision_range", StatModifier.Operation.MULTIPLY, 1.0)
		StatModifierAggregator.reroll_into(mod, group, rng, _FLOOR)
		values.append(mod.value)
	assert_ne(values[0], 1.0, "the re-roll replaced the stale value")
	assert_eq(values[0], values[1], "same seed, same entries in the same order → same value")
