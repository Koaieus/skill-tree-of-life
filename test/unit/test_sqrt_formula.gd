extends GutTest

## #760/#776 — magic damage did not scale legibly from 0.5k to 20k INT. The
## owner pick, revised 2026-09-13: a pure sqrt transfer, no knee. ("The knee
## is not intuitive. possibly we drop it in favor of a pure sqrt
## relationship.") `KneeSqrtFormula` is gone; this is [SqrtFormula].
##
## `divisor` is an owner-tuned `@export` starting value, NOT pinned by this
## file — every assertion below either hand-builds a formula with values the
## test itself sets, or checks a PROPERTY (monotonic, sublinear) that
## survives the owner retuning the shipped default. `.claude/rules/stat-knobs-and-bins.md`.

const BOARD := preload("res://entity/default_entity_board.tres")

var _board: EntityStatBoard = null


func before_each() -> void:
	_board = BOARD.duplicate(true)


func _sqrt(source: StringName, divisor: float) -> SqrtFormula:
	var f := SqrtFormula.new()
	f.source_stat_id = source
	f.divisor = divisor
	return f


## The live modifier off the shipped board, not a hand-rolled copy.
func _shipped(stat_id: StringName) -> SqrtFormula:
	for leaf in StatModifier.flatten_all(BOARD.intrinsic_modifiers):
		if leaf.stat_id == stat_id and leaf.formula is SqrtFormula:
			return leaf.formula
	return null


# --- 1. Strictly increasing --------------------------------------------------

func test_strictly_increasing_across_a_wide_sample() -> void:
	var f := _sqrt(&"intelligence", 1.0)
	var samples := [10, 100, 500, 1000, 5000, 10000, 20000]
	var last := -INF
	for int_value in samples:
		_board.intelligence.base_value = float(int_value)
		var v := f.compute(_board)
		assert_gt(v, last, "INT %d must exceed the previous sample" % int_value)
		last = v


# --- 2. Sublinear everywhere -------------------------------------------------

func test_sublinear_everywhere() -> void:
	# f(4x) <= 2*f(x) + 1 — sqrt(4x) == 2*sqrt(x) exactly, so the "+1" only
	# absorbs the floor's rounding; a linear (RatioFormula-shaped) rule would
	# fail this the moment its own floor rounding didn't happen to line up.
	var f := _sqrt(&"intelligence", 1.0)
	for int_value in [10, 100, 1000, 10000]:
		_board.intelligence.base_value = float(int_value)
		var fx := f.compute(_board)
		_board.intelligence.base_value = float(int_value * 4)
		var f4x := f.compute(_board)
		assert_true(f4x <= 2.0 * fx + 1.0,
			"f(%d)=%.1f should be <= 2*f(%d)+1=%.1f" % [int_value * 4, f4x, int_value, 2.0 * fx + 1.0])


func test_negative_source_is_clamped_not_nan() -> void:
	var f := _sqrt(&"intelligence", 10.0)
	_board.intelligence.base_value = -50.0
	assert_eq(f.compute(_board), 0.0, "a negative source yields 0, never NaN")


func test_zero_divisor_returns_zero_and_errors() -> void:
	var f := _sqrt(&"intelligence", 0.0)
	_board.intelligence.base_value = 500.0
	assert_eq(f.compute(_board), 0.0)
	assert_push_error("SqrtFormula: divisor is 0 for source 'intelligence'")


func test_missing_source_stat_returns_zero() -> void:
	assert_eq(_sqrt(&"not_a_stat", 10.0).compute(_board), 0.0)


# --- Wire round-trip through the codec ---------------------------------------

func test_sqrt_formula_round_trips_through_the_codec() -> void:
	var f := _sqrt(&"intelligence", 10.0)
	f.per_phrase = "10 INT"
	var back := StatModifierCodec.formula_from_dict(f.to_dict())
	assert_true(back is SqrtFormula, "decodes back to a SqrtFormula")
	var s: SqrtFormula = back
	assert_eq(s.source_stat_id, &"intelligence")
	assert_eq(s.divisor, 10.0)
	assert_eq(s.per_phrase, "10 INT")
	_board.intelligence.base_value = 5000.0
	assert_eq(s.compute(_board), f.compute(_board), "and computes the same")


func test_input_ids_strip_an_accessor_token() -> void:
	var f := _sqrt(&"health__current", 10.0)
	assert_eq(f.get_input_ids(), [&"health"] as Array[StringName])


# --- describe_per / describe_clause coverage ---------------------------------

func test_describe_per_is_never_empty() -> void:
	# test_every_board_intrinsic_formula_is_described requires this — a
	# board intrinsic that cannot describe itself fails that suite test.
	assert_ne(_shipped(&"spell_damage").describe_per(), "")


func test_describe_clause_names_the_root_not_a_flat_per_rate() -> void:
	var f := _sqrt(&"intelligence", 20.0)
	var clause := f.describe_clause()
	assert_true(clause.contains("INT"), "clause must name the source stat")
	assert_true(clause.contains("√"), "clause must mark this as a root, not a flat per-rate")


func test_authored_per_phrase_still_wins_for_the_clause() -> void:
	var f := _sqrt(&"intelligence", 10.0)
	f.per_phrase = "spell power"
	assert_eq(f.describe_clause(), " per spell power")
