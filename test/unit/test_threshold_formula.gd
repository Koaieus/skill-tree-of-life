extends GutTest

## #547 — mana-per-turn was `floor(log(INT) / log(10.0))`, which returns 2 at
## INT 1000 on glibc: `log(1000.0)` is one ulp below `3 * log(10.0)`, the ratio
## is 2.9999999999999996, and `floor` turns that into a whole missing point of
## regen. IEEE 754 specifies only `+ - * / sqrt` to be correctly rounded, so
## that is not a glibc bug to wait out — every libm approximates `log`
## differently in the last bits, and derived stats are recomputed on EVERY PEER
## rather than sent, so a Windows client and a Linux host would silently
## disagree for a whole run.
##
## Four things are pinned here:
##   1. Mana-per-turn is exact at every power of ten and on both sides of it —
##      the range the issue asked for, plus the top of the ladder, which the
##      issue's range could not see.
##   2. Sensor-range's replacement is EXACTLY `floor(ln(WIS))` for every
##      integer WIS in range. This migration changes no value; it only removes
##      the libm dependence.
##   3. The ladder saturates at `breakpoints.size()`, deliberately, and the
##      shipped ladders saturate above anything reachable.
##   4. The wire form round-trips — a new StatFormula subclass with no codec
##      tag decodes to null, and loot candidates would silently lose it.

const BOARD := preload("res://entity/default_entity_board.tres")

var _board: EntityStatBoard = null


func before_each() -> void:
	_board = BOARD.duplicate(true)


func _threshold(source: StringName, bps: Array[float]) -> ThresholdFormula:
	var f := ThresholdFormula.new()
	f.source_stat_id = source
	f.breakpoints = bps
	return f


## The live modifier off the shipped board, not a hand-rolled copy — a test
## that builds its own formula proves the class works and nothing about what
## the game actually ships.
func _shipped(stat_id: StringName) -> ThresholdFormula:
	for leaf in StatModifier.flatten_all(BOARD.intrinsic_modifiers):
		if leaf.stat_id == stat_id and leaf.formula is ThresholdFormula:
			return leaf.formula
	return null


# --- 1. Mana per turn --------------------------------------------------------

func test_shipped_mana_ladder_is_exact_at_every_decade() -> void:
	var f := _shipped(&"mana_per_turn")
	assert_not_null(f, "default board grants mana_per_turn via a ThresholdFormula")
	# The issue's range. INT 1000 -> 3 is the bug; the rest are regression cover.
	var cases := {1: 0, 9: 0, 10: 1, 11: 1, 99: 1, 100: 2, 101: 2,
		999: 2, 1000: 3, 1001: 3}
	for int_value in cases:
		_board.intelligence.base_value = float(int_value)
		assert_eq(f.compute(_board), float(cases[int_value]),
			"INT %d -> %d mana/turn" % [int_value, cases[int_value]])


func test_shipped_mana_ladder_keeps_climbing_past_the_issues_range() -> void:
	# The blind spot in the acceptance range: a ladder ending at 1000 passes
	# every case above and is newly WRONG at 10000, where both the old formula
	# and the correct answer give 4.
	var f := _shipped(&"mana_per_turn")
	for pair in [[10000, 4], [100000, 5], [1000000, 6]]:
		_board.intelligence.base_value = float(pair[0])
		assert_eq(f.compute(_board), float(pair[1]),
			"INT %d -> %d mana/turn" % pair)


func test_mana_no_longer_goes_NEGATIVE_at_zero_intelligence() -> void:
	# `floor(log(max(1e-5, float(0))) / log(10.0))` is floor(-5) = -5. A
	# debuff that zeroed INT drained five mana a turn. Deliberate fix, not an
	# accident of the migration.
	var f := _shipped(&"mana_per_turn")
	_board.intelligence.base_value = 0.0
	assert_eq(f.compute(_board), 0.0, "INT 0 grants nothing, never negative")


# --- 2. Sensor range is value-identical to floor(ln(WIS)) --------------------

func test_shipped_sensor_ladder_reproduces_natural_log_exactly() -> void:
	var f := _shipped(&"sensor_range")
	assert_not_null(f, "default board grants sensor_range via a ThresholdFormula")
	# Every integer through the first four steps, then the exact boundaries
	# above — `ceil(e^n)` is where each step lands, and the pair either side of
	# a boundary is the only place a ladder can disagree with the log.
	var probes: Array[int] = []
	for w in range(0, 60):
		probes.append(w)
	for boundary in [149, 404, 1097, 2981, 8104]:
		probes.append(boundary - 1)
		probes.append(boundary)
	for w in probes:
		_board.wisdom.base_value = float(w)
		var expected := floorf(log(maxf(1.0, float(w))))
		assert_eq(f.compute(_board), expected, "WIS %d -> floor(ln) = %d"
			% [w, int(expected)])


func test_the_sensor_ladder_only_reproduces_ln_because_its_input_is_integral() -> void:
	# `ceil(e^n)` is the right rung for INTEGER input and the wrong one for
	# reals: `floor(ln x)` is already 1 at x = 2.71828, while the rung sits at
	# 3.0. That gap is unreachable only because `wisdom` is a
	# `StatDef.ValueType.INT` stat and `Stat._coerce` `roundi`s it, so the
	# formula never sees a fraction — the OLD `floor(log(wisdom))` read the
	# same rounded integer, which is why this migration changes no value.
	#
	# Flip wisdom (or intelligence) to FLOAT and that stops being true. This
	# test is the tripwire: re-rung the ladder on the `e^n` literals, or don't
	# flip the type.
	for stat_id in [&"wisdom", &"intelligence"]:
		var def: StatDef = StatRegistry.get_def(stat_id)
		assert_not_null(def, "%s has a StatDef" % stat_id)
		assert_eq(def.value_type, StatDef.ValueType.INT,
			"%s must stay INT — the threshold ladders are rung for integers" % stat_id)
	_board.wisdom.base_value = 2.9
	assert_eq(float(_board.wisdom.get_value()), 3.0,
		"a fractional base still reads back as an integer")


func test_sensor_phrase_is_still_the_authored_one() -> void:
	# The ladder IS floor(ln WIS), so "log(WIS)" stays honest prose. The
	# Attributes Panel renders it (test_attribute_rules) and the transcendental
	# lint reads `formula = ` lines only, never `per_phrase`.
	assert_eq(_shipped(&"sensor_range").describe_per(), "log(WIS)")


# --- 3. Saturation is a decision, not an accident ---------------------------

func test_a_ladder_saturates_at_its_length() -> void:
	var f := _threshold(&"intelligence", [10.0, 100.0] as Array[float])
	_board.intelligence.base_value = 10_000_000.0
	assert_eq(f.compute(_board), 2.0, "a two-rung ladder tops out at 2")


func test_an_empty_ladder_is_zero_not_an_error() -> void:
	assert_eq(_threshold(&"intelligence", [] as Array[float]).compute(_board), 0.0)


func test_missing_source_stat_returns_zero() -> void:
	assert_eq(_threshold(&"not_a_stat", [1.0] as Array[float]).compute(_board), 0.0)


# --- describe_per ------------------------------------------------------------

func test_geometric_ladder_generates_its_own_multiplier_phrase() -> void:
	# Read off the same array compute() walks, so the shown number and the
	# computed number cannot drift — the RatioFormula principle.
	assert_eq(_shipped(&"mana_per_turn").describe_per(), "×10 INT")


func test_non_geometric_ladder_falls_back_to_the_bare_abbreviation() -> void:
	assert_eq(_threshold(&"wisdom", [3.0, 8.0, 21.0] as Array[float]).describe_per(), "WIS")


func test_a_ladder_not_starting_at_its_ratio_is_not_geometric() -> void:
	# [1, 10, 100] steps by ×10 but starts at 1, so "×10 WIS" would misdescribe
	# the first rung. Falls back rather than lying.
	assert_eq(_threshold(&"wisdom", [1.0, 10.0, 100.0] as Array[float]).describe_per(), "WIS")


# --- 4. Wire form ------------------------------------------------------------

func test_threshold_formula_round_trips_through_the_codec() -> void:
	var f := _threshold(&"intelligence", [10.0, 100.0, 1000.0] as Array[float])
	f.per_phrase = "×10 INT"
	var back := StatModifierCodec.formula_from_dict(f.to_dict())
	assert_true(back is ThresholdFormula, "decodes back to a ThresholdFormula")
	var t: ThresholdFormula = back
	assert_eq(t.source_stat_id, &"intelligence")
	assert_eq(t.breakpoints, [10.0, 100.0, 1000.0] as Array[float])
	assert_eq(t.per_phrase, "×10 INT")
	_board.intelligence.base_value = 1000.0
	assert_eq(t.compute(_board), f.compute(_board), "and computes the same")


func test_input_ids_strip_an_accessor_token() -> void:
	var f := _threshold(&"health__current", [10.0] as Array[float])
	assert_eq(f.get_input_ids(), [&"health"] as Array[StringName])


# --- 5. The lint is the guard against the next one --------------------------

func test_no_transcendental_survives_in_a_shipped_board_formula() -> void:
	# The narrow, in-suite half of `mise run lint-transcendentals` — a .tres
	# edit that reintroduces one fails here too, not only in the lint task.
	var banned := ["log(", "exp(", "pow(", "sin(", "cos(", "tan("]
	for leaf in StatModifier.flatten_all(BOARD.intrinsic_modifiers):
		if not (leaf.formula is ExpressionFormula):
			continue
		var text: String = (leaf.formula as ExpressionFormula).formula
		for token in banned:
			assert_false(text.contains(token),
				"'%s' on stat '%s' uses %s" % [text, leaf.stat_id, token])
