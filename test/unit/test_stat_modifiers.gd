extends GutTest

## Canonical pipeline + reactivity tests for StatModifier.
##
## Pipeline: SET short-circuits; else
##   result = (base + Σ ADD_BASE) × (1 + Σ INCREASE/100) × Π MULTIPLY + Σ ADD_BONUS
## INCREASE is additive (PoE); MULTIPLY composes.
##
## Reactivity: editing modifier.value or any formula source stat must dirty
## the target via the same Resource.changed path.

const _STR_DEF := preload("res://stats_system/defs/strength.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")


func _stat(base: float = 0.0) -> ScalarStat:
	var s := ScalarStat.new()
	s.definition = _STR_DEF
	s.base_value = base
	return s


func _mod(op: int, value: float, formula: StatFormula = null) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = op as StatModifier.Operation
	m.value = value
	m.formula = formula
	return m


func _board() -> EntityStatBoard:
	return _BOARD.duplicate(true)


# --- Pipeline ---------------------------------------------------------------

func test_no_modifiers_returns_base() -> void:
	var s := _stat(7.0)
	assert_eq(s.get_value(), 7)


func test_add_base_plus_one() -> void:
	var s := _stat(0.0)
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0))
	assert_eq(s.get_value(), 1)


func test_canonical_pipeline_example() -> void:
	# (0 + 1) × (1 + 0.5 + 0.5) × 2 × 2 = 8
	var s := _stat(0.0)
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0))
	s.add_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	s.add_modifier(_mod(StatModifier.Operation.INCREASE, 50.0))
	s.add_modifier(_mod(StatModifier.Operation.INCREASE, 50.0))
	s.add_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	assert_eq(s.get_value(), 8)


func test_increase_is_additive_not_compounding() -> void:
	# Five +20% must give +100% (×2), NOT (1.2)^5 ≈ ×2.49.
	var s := _stat(10.0)
	for i in 5:
		s.add_modifier(_mod(StatModifier.Operation.INCREASE, 20.0))
	assert_eq(s.get_value(), 20)


func test_add_bonus_bypasses_multipliers() -> void:
	# (0 + 1) × 2 + 5 = 7
	var s := _stat(0.0)
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0))
	s.add_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	s.add_modifier(_mod(StatModifier.Operation.ADD_BONUS, 5.0))
	assert_eq(s.get_value(), 7)


func test_set_short_circuits() -> void:
	var s := _stat(0.0)
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 99.0))
	s.add_modifier(_mod(StatModifier.Operation.MULTIPLY, 99.0))
	s.add_modifier(_mod(StatModifier.Operation.SET, 42.0))
	assert_eq(s.get_value(), 42)


func test_set_higher_priority_wins() -> void:
	var s := _stat(0.0)
	var low := _mod(StatModifier.Operation.SET, 10.0); low.priority = 1
	var high := _mod(StatModifier.Operation.SET, 99.0); high.priority = 5
	s.add_modifier(low)
	s.add_modifier(high)
	assert_eq(s.get_value(), 99)


func test_set_equal_priority_last_in_wins() -> void:
	var s := _stat(0.0)
	s.add_modifier(_mod(StatModifier.Operation.SET, 10.0))
	s.add_modifier(_mod(StatModifier.Operation.SET, 20.0))
	assert_eq(s.get_value(), 20)


func test_remove_reverts_value() -> void:
	var s := _stat(7.0)
	var m := _mod(StatModifier.Operation.ADD_BASE, 5.0)
	s.add_modifier(m)
	assert_eq(s.get_value(), 12)
	s.remove_modifier(m)
	assert_eq(s.get_value(), 7)


func test_remove_set_falls_back_to_pipeline() -> void:
	var s := _stat(0.0)
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 3.0))
	var set_mod := _mod(StatModifier.Operation.SET, 42.0)
	s.add_modifier(set_mod)
	assert_eq(s.get_value(), 42)
	s.remove_modifier(set_mod)
	assert_eq(s.get_value(), 3)


# --- Reactivity / dirty tracking ----------------------------------------

func test_value_changed_fires_on_add() -> void:
	var s := _stat(0.0)
	watch_signals(s)
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0))
	assert_signal_emitted(s, "value_changed")


func test_value_changed_fires_on_remove() -> void:
	var s := _stat(0.0)
	var m := _mod(StatModifier.Operation.ADD_BASE, 1.0)
	s.add_modifier(m)
	watch_signals(s)
	s.remove_modifier(m)
	assert_signal_emitted(s, "value_changed")


func test_editing_modifier_value_propagates_to_stat() -> void:
	var s := _stat(0.0)
	var m := _mod(StatModifier.Operation.ADD_BASE, 1.0)
	s.add_modifier(m)
	watch_signals(s)
	m.value = 5.0
	assert_signal_emitted(s, "value_changed")
	assert_eq(s.get_value(), 5)


func test_editing_modifier_value_updates_increase_bin() -> void:
	# Same path as ADD_BASE but exercises the additive INCREASE bin.
	var s := _stat(10.0)
	var m := _mod(StatModifier.Operation.INCREASE, 50.0)
	s.add_modifier(m)
	assert_eq(s.get_value(), 15)
	m.value = 100.0
	assert_eq(s.get_value(), 20)


# --- Formulas ----------------------------------------------------------

func test_formula_pass_through_with_unit_value() -> void:
	# value=1 + LinearFormula(dexterity=10) → +10 strength.
	var board := _board()
	board.dexterity.base_value = 10.0
	board.strength.base_value = 0.0
	var lf := LinearFormula.new()
	lf.source_stat_id = &"dexterity"
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0, lf))
	assert_eq(board.strength.get_value(), 10)


func test_formula_value_acts_as_coefficient() -> void:
	# value=3 + LinearFormula(dexterity=10) → +30 strength.
	var board := _board()
	board.dexterity.base_value = 10.0
	board.strength.base_value = 0.0
	var lf := LinearFormula.new()
	lf.source_stat_id = &"dexterity"
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 3.0, lf))
	assert_eq(board.strength.get_value(), 30)


func test_formula_source_change_via_modifier_propagates() -> void:
	var board := _board()
	board.strength.base_value = 0.0
	board.dexterity.base_value = 5.0
	var lf := LinearFormula.new()
	lf.source_stat_id = &"dexterity"
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0, lf))
	var before := int(board.strength.get_value())
	var bump := StatModifier.new()
	bump.stat_id = &"dexterity"
	bump.operation = StatModifier.Operation.ADD_BASE
	bump.value = 10.0
	board.add_modifier(bump)
	assert_eq(int(board.strength.get_value()) - before, 10)


func test_formula_source_change_via_base_value_propagates() -> void:
	# Direct base_value writes must dirty downstream formulas — same reactive
	# path as the modifier route above.
	var board := _board()
	board.strength.base_value = 0.0
	board.dexterity.base_value = 5.0
	var lf := LinearFormula.new()
	lf.source_stat_id = &"dexterity"
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0, lf))
	var before := int(board.strength.get_value())
	board.dexterity.base_value = 15.0
	assert_eq(int(board.strength.get_value()) - before, 10)


func test_base_value_change_emits_value_changed() -> void:
	var s := _stat(0.0)
	watch_signals(s)
	s.base_value = 5.0
	assert_signal_emitted(s, "value_changed")
	assert_eq(s.get_value(), 5)


func test_base_value_same_value_write_is_noop() -> void:
	var s := _stat(7.0)
	watch_signals(s)
	s.base_value = 7.0
	assert_signal_not_emitted(s, "value_changed")


func test_formula_mixed_with_static_modifiers() -> void:
	# base 0 + [+5 base, ×2, +50%, +DEX(10) base] → (0+5+10) × 1.5 × 2 = 45
	var board := _board()
	board.dexterity.base_value = 10.0
	board.strength.base_value = 0.0
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 5.0))
	board.add_modifier(_mod(StatModifier.Operation.MULTIPLY, 2.0))
	board.add_modifier(_mod(StatModifier.Operation.INCREASE, 50.0))
	var lf := LinearFormula.new()
	lf.source_stat_id = &"dexterity"
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0, lf))
	assert_eq(board.strength.get_value(), 45)


func test_expression_formula_floor_per_ten() -> void:
	# Mirrors the +1 sensor_range per 10 PER intrinsic shape.
	var board := _board()
	board.strength.base_value = 0.0
	board.perception.base_value = 25.0
	var ef := ExpressionFormula.new()
	ef.formula = "floor(perception / 10.0)"
	ef.inputs = [&"perception"]
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 1.0, ef))
	assert_eq(board.strength.get_value(), 2)  # floor(25/10) = 2


func test_unbind_disconnects_source_signal() -> void:
	# After remove_modifier, mutating the source must NOT touch the target stat.
	var board := _board()
	board.strength.base_value = 0.0
	board.dexterity.base_value = 5.0
	var lf := LinearFormula.new()
	lf.source_stat_id = &"dexterity"
	var fm := _mod(StatModifier.Operation.ADD_BASE, 1.0, lf)
	board.add_modifier(fm)
	board.remove_modifier(fm)
	var snapshot := int(board.strength.get_value())
	var bump := StatModifier.new()
	bump.stat_id = &"dexterity"
	bump.operation = StatModifier.Operation.ADD_BASE
	bump.value = 100.0
	board.add_modifier(bump)
	assert_eq(int(board.strength.get_value()), snapshot)


# --- Intrinsics --------------------------------------------------------

func test_apply_intrinsics_per_to_vision() -> void:
	# Default board: PER intrinsic is +2% vision_range per PER (INCREASE). Don't
	# pin the board's authored PER/base_value here — that's tuning, not the
	# behavior under test — just that a positive PER raises vision above base.
	var board := _board()
	var base: float = board.vision_range.get_value()
	board.apply_intrinsics()
	assert_gt(board.vision_range.get_value(), base,
			"PER intrinsic must raise vision_range above base")


func test_apply_intrinsics_two_boards_dont_share_state() -> void:
	# _board() deep-duplicates _BOARD per call, so `a` and `b` mount separate
	# intrinsic_modifiers arrays from the start — apply_intrinsics() itself no
	# longer duplicates (#377), and doesn't need to: bumping DEX on one must
	# still not move the other's range.
	var a := _board()
	var b := _board()
	a.apply_intrinsics()
	b.apply_intrinsics()
	var bump := StatModifier.new()
	bump.stat_id = &"dexterity"
	bump.operation = StatModifier.Operation.ADD_BASE
	bump.value = 50.0
	a.add_modifier(bump)
	# a.range scales with a.dex (now 60); b.range scales with b.dex (still 10).
	assert_ne(a.range.get_value(), b.range.get_value())


func test_same_modifier_instance_shared_across_two_boards_computes_independently() -> void:
	# #377's actual point: ONE StatModifier instance, applied to TWO different
	# boards via add_modifier — not two duplicated copies. Each board binds
	# its own reactive wiring (StatBoard.bind_modifier), so each computes off
	# its OWN source stat, and a source change on one board never touches the
	# other's computed value.
	var a := _board()
	var b := _board()
	a.dexterity.base_value = 10.0
	b.dexterity.base_value = 100.0
	a.strength.base_value = 0.0
	b.strength.base_value = 0.0
	var lf := LinearFormula.new()
	lf.source_stat_id = &"dexterity"
	var shared := _mod(StatModifier.Operation.ADD_BASE, 1.0, lf)
	a.add_modifier(shared)
	b.add_modifier(shared)
	assert_eq(int(a.strength.get_value()), 10, "board A reads its own dexterity")
	assert_eq(int(b.strength.get_value()), 100, "board B reads its own dexterity, not A's")
	# A source change on board A must not touch board B's computed value.
	a.dexterity.base_value = 999.0
	assert_eq(int(b.strength.get_value()), 100, "board B is untouched by A's source change")
	assert_eq(int(a.strength.get_value()), 999, "board A recomputed off its own source")
