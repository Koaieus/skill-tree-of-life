@tool
class_name RatioFormula
extends StatFormula

## Integer-division scaling — "+1 per N points of some stat", the single most
## common intrinsic shape in the game (#289). Computes
## `floor(source / divisor)`; the modifier's `value` carries the coefficient,
## so "+2 blade size per 20 STR" is `value = 2` + `RatioFormula(strength, 20)`.
##
## Replaces six hand-written [ExpressionFormula]s whose strings had already
## drifted apart in idiom (`floor(float(x) / 10.0)` vs `floor(x / 20.)`) and
## whose divisors had drifted out of sync with the prose describing them in
## four separate places. With the divisor as a typed field, the displayed
## number and the computed number cannot disagree — [method describe_per]
## renders the same `divisor` that [method compute] divides by.
##
## Use [ExpressionFormula] when the shape genuinely isn't a ratio (log decades,
## products of two stats); use [LinearFormula] for an ungated passthrough.

## The stat being divided.
@export var source_stat_id: StringName = &""

## Points of `source_stat_id` per step. `10` reads "+1 per 10 STR".
@export var divisor: float = 10.0


func get_input_ids() -> Array[StringName]:
	return [source_stat_id]


func compute(board: StatBoard) -> float:
	if is_zero_approx(divisor):
		push_error("RatioFormula: divisor is 0 for source '%s'" % source_stat_id)
		return 0.0
	var s := board.get_stat(source_stat_id)
	if s == null:
		return 0.0
	return floorf(float(s.get_value()) / divisor)


## "20 STR" — or just "STR" at divisor 1, where the number is noise. An
## authored [member per_phrase] still wins, for the rare ratio that wants
## bespoke wording.
func describe_per() -> String:
	if not per_phrase.is_empty():
		return per_phrase
	var abbr := _abbrev(source_stat_id)
	if is_equal_approx(divisor, 1.0):
		return abbr
	return "%s %s" % [_trim(divisor), abbr]
