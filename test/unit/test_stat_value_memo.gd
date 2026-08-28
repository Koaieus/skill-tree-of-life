extends GutTest

## `Stat.get_value()` memo (#470, scope-amended work item 2 only — the
## fan-out hoist and cascade batching in the original spec were struck; #660
## deletes that machinery wholesale).
##
## Two things this pins:
## 1. The memo is behind a dirty flag that every mutation path invalidates —
##    a warm read must never serve a value stale relative to the current
##    base_value / modifier set.
## 2. #463's stable-iteration-order obligation: the memo must aggregate the
##    same bins in the same insertion order the live pipeline always used,
##    never re-derived some other way. Pinned with values chosen so any
##    CORRECT (order-preserving) implementation reproduces bit-identical
##    results regardless of which of the shuffled orders built the stat —
##    while still being sensitive to a broken implementation that drops,
##    reorders, or partially caches a modifier mid-build.

const _FLOAT_DEF := preload("res://stats_system/defs/crit_chance.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")


func _float_stat(base: float = 0.0) -> ScalarStat:
	# crit_chance is FLOAT-typed (unlike strength/INT), so get_value() isn't
	# roundi()'d — a memo bug that lands on the wrong last bit would otherwise
	# be masked by coercion.
	var s := ScalarStat.new()
	s.definition = _FLOAT_DEF
	s.base_value = base
	return s


func _mod(op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"crit_chance"
	m.operation = op
	m.value = value
	return m


func _board() -> EntityStatBoard:
	return _BOARD.duplicate(true)


# --- Dirty-flag correctness --------------------------------------------------


func test_first_read_computes_and_is_correct() -> void:
	var s := _float_stat(3.0)
	assert_almost_eq(float(s.get_value()), 3.0, 0.0001)


func test_repeated_reads_stay_correct_with_no_mutation_between() -> void:
	var s := _float_stat(3.0)
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 2.0))
	var first := float(s.get_value())
	var second := float(s.get_value())
	assert_eq(first, second, "a warm memo must return the exact same bits as the read that warmed it")
	assert_almost_eq(first, 5.0, 0.0001)


func test_add_modifier_invalidates_a_warm_memo() -> void:
	var s := _float_stat(1.0)
	var before := float(s.get_value())  # warms the memo
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 10.0))
	assert_almost_eq(float(s.get_value()), before + 10.0, 0.0001,
		"adding a modifier after a warm read must not serve the pre-add cache")


func test_remove_modifier_invalidates_a_warm_memo() -> void:
	var s := _float_stat(1.0)
	var m := _mod(StatModifier.Operation.ADD_BASE, 10.0)
	s.add_modifier(m)
	var before := float(s.get_value())  # warms the memo at base+10
	s.remove_modifier(m)
	assert_almost_eq(float(s.get_value()), before - 10.0, 0.0001,
		"removing a modifier after a warm read must not serve the pre-remove cache")


func test_base_value_write_invalidates_a_warm_memo() -> void:
	var s := _float_stat(1.0)
	var before := float(s.get_value())  # warms the memo
	s.base_value = 50.0
	assert_almost_eq(float(s.get_value()), before + 49.0, 0.0001,
		"writing base_value after a warm read must not serve the stale cache")


## Same reactive path `test_stat_modifiers.gd`'s formula tests use — a
## board-bound modifier with a LinearFormula source — but with a WARM read
## taken before the source moves, so this specifically exercises the memo
## rather than the (already-covered) formula wiring itself.
func test_a_reactive_formula_source_change_invalidates_a_warm_memo() -> void:
	var board := _board()
	board.dexterity.base_value = 5.0
	board.crit_chance.base_value = 0.0
	var lf := LinearFormula.new()
	lf.source_stat_id = &"dexterity"
	var m := StatModifier.new()
	m.stat_id = &"crit_chance"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 1.0
	m.formula = lf
	board.add_modifier(m)

	var before := float(board.crit_chance.get_value())  # warms the memo
	board.dexterity.base_value = 15.0  # fires m.changed -> _on_dependent_modifier_changed
	assert_almost_eq(float(board.crit_chance.get_value()), before + 10.0, 0.0001,
		"a bound formula source moving must invalidate the dependent's warm memo")


# --- #463 stable-order pin ---------------------------------------------------


## Values are exact under IEEE-754 double addition/multiplication in ANY
## grouping (small integers and powers of two never round when combined), so
## a correct order-preserving fold gives the identical result regardless of
## which of the two shuffles built the bins. A broken memo that skips,
## duplicates, or partially snapshots a modifier during a shuffled build would
## land on a different (and also exact, so NOT masked by tolerance) total —
## which is why this asserts exact equality, not assert_almost_eq.
func test_get_value_is_identical_under_shuffled_modifier_insertion_order() -> void:
	var add_base_values := [4.0, -1.0, 8.0, 2.0]
	var increase_values := [25.0, 25.0, 50.0]
	var bonus_values := [3.0, -3.0, 6.0]
	var multiply_values := [2.0, 0.5, 4.0]

	var order_a := _build_shuffled(add_base_values, increase_values, bonus_values, multiply_values, 0)
	var order_b := _build_shuffled(add_base_values, increase_values, bonus_values, multiply_values, 1)

	var stat_a := _float_stat(5.0)
	for m in order_a:
		stat_a.add_modifier(m)
	var stat_b := _float_stat(5.0)
	for m in order_b:
		stat_b.add_modifier(m)

	assert_eq(float(stat_a.get_value()), float(stat_b.get_value()),
		"an aggregated stat value must be identical under shuffled modifier insertion order")


## Rotates which OP-GROUP goes first before interleaving, so `order_a`/
## `order_b` above insert the same modifier SET (same values, same ops) in two
## different sequences — e.g. ADD_BASE-first vs MULTIPLY-first.
func _build_shuffled(add_base: Array, increase: Array, bonus: Array, multiply: Array, shift: int) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var groups := [
		[StatModifier.Operation.ADD_BASE, add_base],
		[StatModifier.Operation.INCREASE, increase],
		[StatModifier.Operation.ADD_BONUS, bonus],
		[StatModifier.Operation.MULTIPLY, multiply],
	]
	var n := groups.size()
	for i in n:
		var entry: Array = groups[(i + shift) % n]
		var op: StatModifier.Operation = entry[0]
		for v in entry[1]:
			out.append(_mod(op, v))
	return out
