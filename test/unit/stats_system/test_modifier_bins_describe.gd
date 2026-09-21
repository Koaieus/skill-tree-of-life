extends GutTest

## The merged-pipeline door: ModifierBins.resolve → FoldTerms (plain numbers,
## no boards), Stat.resolve_with (bins + overlays), and FoldTerms.describe —
## a pure formatter over the resolved terms. A readout never re-folds bins.
##
## Hand-built stats under an unregistered id (except the formula fixture,
## which binds to the default board's `level` so a MULTIPLY has a real
## formula source).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _ID := &"describe_test_stat"


func _terms(add := 0.0, inc := 0.0, bon := 0.0, mult := 1.0, set_value: Variant = null) -> FoldTerms:
	var t := FoldTerms.new()
	t.add = add
	t.inc = inc
	t.bon = bon
	t.mult = mult
	t.set_value = set_value
	return t


func _bins(add := 0.0, inc := 0.0, bon := 0.0) -> ModifierBins:
	var b := ModifierBins.new()
	b.base_add = add
	b.increase_sum = inc
	b.bonus_add = bon
	return b


func _stat(base: float) -> ScalarStat:
	var d := StatDef.new()
	d.id = _ID
	d.value_type = StatDef.ValueType.FLOAT
	var s := ScalarStat.new()
	s.definition = d
	s.base_value = base
	return s


func _mod(op: int, value: float, formula: StatFormula = null) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = op as StatModifier.Operation
	m.value = value
	m.formula = formula
	return m


# --- describe ---------------------------------------------------------------

func test_describe_set_winner() -> void:
	assert_eq(_terms(3.0, 20.0, 2.0, 1.5, 5.0).describe(), "= 5")


func test_describe_nothing() -> void:
	assert_eq(_terms().describe(), "X")


func test_describe_add_only() -> void:
	assert_eq(_terms(3.0).describe(), "X+3")


func test_describe_negative_add() -> void:
	assert_eq(_terms(-3.0).describe(), "X−3")


func test_describe_inc_only() -> void:
	assert_eq(_terms(0.0, 20.0).describe(), "X × 1.2")


func test_describe_add_and_factor() -> void:
	# (1 + 20/100) × 1.25 = 1.5 — inc and multipliers fold to one factor.
	assert_eq(_terms(3.0, 20.0, 0.0, 1.25).describe(), "(X+3) × 1.5")


func test_describe_add_factor_bonus() -> void:
	assert_eq(_terms(3.0, 0.0, 2.0, 1.5).describe(), "(X+3) × 1.5 + 2")


func test_describe_custom_base_label() -> void:
	assert_eq(_terms(3.0).describe("STR"), "STR+3")


# --- resolve ----------------------------------------------------------------

## Source A is a board-bound entity stat carrying a formula MULTIPLY (×0.5 per
## level, level 3 → ×1.5) — it MUST be resolved on A's own board. Source B is a
## bare overlay. A merge that concatenated multipliers under one null board
## would degrade A's factor to the static 0.5.
func _formula_fixture() -> Array:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	board.level.base_value = 3.0
	board.strength.base_value = 10.0
	var lin := LinearFormula.new()
	lin.source_stat_id = &"level"
	board.add_modifier(_mod(StatModifier.Operation.MULTIPLY, 0.5, lin))
	board.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 4.0))
	var overlay := _bins(2.0, 50.0, 7.0)
	return [board.strength, overlay]


func test_resolve_two_sources_hand_summed_with_formula_multiply() -> void:
	var fx := _formula_fixture()
	var s: Stat = fx[0]
	var overlay: ModifierBins = fx[1]
	var sources: Array[ModifierBins] = [s.bins, overlay]
	var t := ModifierBins.resolve(sources)
	assert_almost_eq(t.add, 6.0, 0.0001, "Σ base_add")
	assert_almost_eq(t.inc, 50.0, 0.0001, "Σ increase_sum")
	assert_almost_eq(t.bon, 7.0, 0.0001, "Σ bonus_add")
	assert_almost_eq(t.mult, 1.5, 0.0001, "formula MULTIPLY resolved on its own board")
	assert_null(t.set_value)


func test_compute_unchanged_for_formula_fixture() -> void:
	var fx := _formula_fixture()
	var s: Stat = fx[0]
	var sources: Array[ModifierBins] = [s.bins, fx[1]]
	# (10 + 6) × 1.5 × 1.5 + 7 = 43
	assert_almost_eq(ModifierBins.compute(10.0, sources), 43.0, 0.0001)


func test_resolve_set_winner_carries_effective_value() -> void:
	var s := _stat(1.0)
	s.add_modifier(_mod(StatModifier.Operation.SET, 9.0))
	var sources: Array[ModifierBins] = [s.bins, _bins(2.0)]
	var t := ModifierBins.resolve(sources)
	assert_eq(t.set_value, 9.0)
	assert_eq(t.describe(), "= 9")


func test_stat_resolve_with_includes_overlay_base_add() -> void:
	var s := _stat(1.0)
	s.add_modifier(_mod(StatModifier.Operation.ADD_BASE, 3.0))
	var overlays: Array[ModifierBins] = [_bins(2.0)]
	var t := s.resolve_with(overlays)
	assert_almost_eq(t.add, 5.0, 0.0001, "own bins + overlay base_add")
	assert_eq(t.describe(), "X+5")
