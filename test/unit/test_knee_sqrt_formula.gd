extends GutTest

## #760 — magic damage did not scale legibly from 0.5k to 20k INT. The owner
## pick (2026-09-10): linear below a knee, sqrt above it — the runaway stat
## (20k INT at the LAN playtest) is intentional and stays fun; only the
## TRANSFER into spell damage was off.
##
## `knee` and `divisor` are owner-tuned `@export` starting values, NOT pinned
## by this file — every assertion below either hand-builds a formula with
## values the test itself sets, or checks a PROPERTY (monotonic, sublinear,
## continuous) that survives the owner retuning the shipped defaults.
## `.claude/rules/stat-knobs-and-bins.md`.

const BOARD := preload("res://entity/default_entity_board.tres")

## Real headroom below the 6.3x the starting values (K=500, d=10) give, and
## still tight enough to fail a log-like curve (1.6x over the same span)
## outright. Owned by this test file, per the issue's acceptance spec.
const MIN_SPREAD := 4.0

var _board: EntityStatBoard = null


func before_each() -> void:
	_board = BOARD.duplicate(true)


func _knee_sqrt(source: StringName, divisor: float, knee: float) -> KneeSqrtFormula:
	var f := KneeSqrtFormula.new()
	f.source_stat_id = source
	f.divisor = divisor
	f.knee = knee
	return f


func _ratio(source: StringName, divisor: float) -> RatioFormula:
	var f := RatioFormula.new()
	f.source_stat_id = source
	f.divisor = divisor
	return f


## The live modifier off the shipped board, not a hand-rolled copy.
func _shipped(stat_id: StringName) -> KneeSqrtFormula:
	for leaf in StatModifier.flatten_all(BOARD.intrinsic_modifiers):
		if leaf.stat_id == stat_id and leaf.formula is KneeSqrtFormula:
			return leaf.formula
	return null


# --- 1. Strictly increasing across the owner's sample points ----------------

func test_strictly_increasing_across_the_owners_sample_points() -> void:
	var f := _knee_sqrt(&"intelligence", 10.0, 500.0)
	var samples := [500, 1000, 5000, 10000, 20000]
	var last := -INF
	for int_value in samples:
		_board.intelligence.base_value = float(int_value)
		var v := f.compute(_board)
		assert_gt(v, last, "INT %d must exceed the previous sample" % int_value)
		last = v


# --- 2. Sublinear above the knee ---------------------------------------------

func test_sublinear_above_the_knee() -> void:
	# f(2x) < 2*f(x) for x > knee. This is the assert that is RED against a
	# plain RatioFormula (exactly linear, f(2x) == 2*f(x) always).
	var f := _knee_sqrt(&"intelligence", 10.0, 500.0)
	for int_value in [1000, 5000, 10000]:
		_board.intelligence.base_value = float(int_value)
		var fx := f.compute(_board)
		_board.intelligence.base_value = float(int_value * 2)
		var f2x := f.compute(_board)
		assert_true(f2x < 2.0 * fx,
			"f(%d)=%.1f should be < 2*f(%d)=%.1f" % [int_value * 2, f2x, int_value, fx])


# --- 3. Differentiation floor -------------------------------------------------

func test_differentiation_floor_between_the_extremes() -> void:
	var f := _knee_sqrt(&"intelligence", 10.0, 500.0)
	_board.intelligence.base_value = 500.0
	var low := f.compute(_board)
	_board.intelligence.base_value = 20000.0
	var high := f.compute(_board)
	assert_true(low > 0.0, "low sample must be nonzero for the ratio to mean anything")
	assert_true(high / low >= MIN_SPREAD,
		"f(20000)/f(500) = %.2f must be >= MIN_SPREAD %.1f" % [high / low, MIN_SPREAD])


# --- 4. Continuity at the knee ------------------------------------------------

func test_continuous_at_the_knee() -> void:
	var divisor := 10.0
	var knee := 500.0
	var f := _knee_sqrt(&"intelligence", divisor, knee)
	_board.intelligence.base_value = knee
	assert_eq(f.compute(_board), floorf(knee / divisor),
		"at INT == knee, the curve must equal the linear branch exactly")


# --- 5. Below-knee passthrough is byte-identical to today -------------------

func test_below_knee_matches_ratio_formula_exactly() -> void:
	var divisor := 10.0
	var knee := 500.0
	var knee_sqrt := _knee_sqrt(&"intelligence", divisor, knee)
	var ratio := _ratio(&"intelligence", divisor)
	for int_value in [0, 1, 9, 50, 100, 250, 499]:
		_board.intelligence.base_value = float(int_value)
		assert_eq(knee_sqrt.compute(_board), ratio.compute(_board),
			"INT %d below the knee must match RatioFormula exactly" % int_value)


func test_negative_source_is_clamped_not_nan() -> void:
	var f := _knee_sqrt(&"intelligence", 10.0, 500.0)
	_board.intelligence.base_value = -50.0
	assert_eq(f.compute(_board), 0.0, "a negative source yields 0, never NaN")


func test_zero_divisor_returns_zero_and_errors() -> void:
	var f := _knee_sqrt(&"intelligence", 0.0, 500.0)
	_board.intelligence.base_value = 500.0
	assert_eq(f.compute(_board), 0.0)
	assert_push_error("KneeSqrtFormula: divisor is 0 for source 'intelligence'")


func test_missing_source_stat_returns_zero() -> void:
	assert_eq(_knee_sqrt(&"not_a_stat", 10.0, 500.0).compute(_board), 0.0)


# --- 6. Wire round-trip through the codec ------------------------------------

func test_knee_sqrt_formula_round_trips_through_the_codec() -> void:
	var f := _knee_sqrt(&"intelligence", 10.0, 500.0)
	f.per_phrase = "10 INT"
	var back := StatModifierCodec.formula_from_dict(f.to_dict())
	assert_true(back is KneeSqrtFormula, "decodes back to a KneeSqrtFormula")
	var k: KneeSqrtFormula = back
	assert_eq(k.source_stat_id, &"intelligence")
	assert_eq(k.divisor, 10.0)
	assert_eq(k.knee, 500.0)
	assert_eq(k.per_phrase, "10 INT")
	_board.intelligence.base_value = 5000.0
	assert_eq(k.compute(_board), f.compute(_board), "and computes the same")


func test_input_ids_strip_an_accessor_token() -> void:
	var f := _knee_sqrt(&"health__current", 10.0, 500.0)
	assert_eq(f.get_input_ids(), [&"health"] as Array[StringName])


# --- describe_per / describe_clause coverage ---------------------------------

func test_describe_per_is_never_empty() -> void:
	# test_every_board_intrinsic_formula_is_described requires this — a
	# board intrinsic that cannot describe itself fails that suite test.
	assert_ne(_shipped(&"spell_damage").describe_per(), "")


func test_describe_clause_names_the_bend_not_a_flat_per_rate() -> void:
	var f := _knee_sqrt(&"intelligence", 10.0, 500.0)
	var clause := f.describe_clause()
	assert_true(clause.contains("INT"), "clause must name the source stat")
	assert_true(clause.contains("500"), "clause must name the knee value")


func test_authored_per_phrase_still_wins_for_the_clause() -> void:
	var f := _knee_sqrt(&"intelligence", 10.0, 500.0)
	f.per_phrase = "spell power"
	assert_eq(f.describe_clause(), " per spell power")
