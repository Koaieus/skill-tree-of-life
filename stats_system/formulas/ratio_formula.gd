@tool
class_name RatioFormula
extends StatFormula

## Linear scaling with a human divisor — "+1 per N points of some stat", the
## single most common intrinsic shape in the game (#289). Computes
## `source / divisor` as a LINE (#891, ADR 0016): no floor here — the target
## stat coerces its finished total once, after every bin, so `% increased` on
## the target yields `+1 +1 +1` rather than a burst and a merged fractional
## rule hands out nothing until its step is actually attained. The modifier's
## `value` carries the coefficient, so "+2 blade size per 20 STR" is
## `value = 2` + `RatioFormula(strength, 20)`; loot merges land in `value`
## (#775) and the divisor stays the authored knob.
##
## Replaces six hand-written [ExpressionFormula]s whose strings had already
## drifted apart in idiom (`floor(float(x) / 10.0)` vs `floor(x / 20.)`) and
## whose divisors had drifted out of sync with the prose describing them in
## four separate places. With the divisor as a typed field, the displayed
## number and the computed number cannot disagree: [method describe_per]
## renders `divisor / value` and [method display_coefficient] renders `1` (or
## `value / divisor` and `1` once that step drops below a point of source) —
## both read off the same two fields [method compute] multiplies, with no
## third number anywhere to drift. `value = 1` prints byte-identical to the
## pre-#891 "+1 Blade Damage per 20 STR".
##
## Use [ExpressionFormula] when the shape genuinely isn't a ratio (log decades,
## products of two stats); use [LinearFormula] for an ungated passthrough.

## The stat being divided. Accepts a bare `<stat_id>` (reads the computed
## value / cap) or a `<stat_id>__<accessor>` token (reads a named accessor —
## see [method Stat.read_accessor]); the formula layer splits the token.
@export var source_stat_id: StringName = &""

## Points of `source_stat_id` per step. `10` reads "+1 per 10 STR".
@export var divisor: float = 10.0


func to_dict() -> Dictionary:
	var d := super()
	d["type"] = StatModifierCodec.TAG_RATIO
	d["source_stat_id"] = source_stat_id
	d["divisor"] = divisor
	return d


func read_dict(d: Dictionary) -> void:
	super(d)
	source_stat_id = StringName(d.get("source_stat_id", &""))
	divisor = float(d.get("divisor", 10.0))


func get_input_ids() -> Array[StringName]:
	return [StatFormula.base_of(source_stat_id)]


func compute(board: StatBoard) -> float:
	if is_zero_approx(divisor):
		push_error("RatioFormula: divisor is 0 for source '%s'" % source_stat_id)
		return 0.0
	var s := board.get_stat(StatFormula.base_of(source_stat_id))
	if s == null:
		return 0.0
	var v: Variant = s.read_accessor(StatFormula.accessor_of(source_stat_id))
	return float(v) / divisor


## Points of source per displayed unit of the target, for a modifier carrying
## [param value] as its coefficient: `divisor / |value|`. A step below one
## point of source has nothing to say here — the unit flips to the other side
## (see [method display_coefficient]) and the phrase is the bare abbreviation.
## A non-positive value keeps the authored divisor so a `+0` or a penalty rule
## still reads its own knob.
func _step(value: float) -> float:
	if value <= 0.0:
		return divisor
	return divisor / value


## The numerator [method StatModifier.format] prints: `1` while the step is at
## least a point of source ("+1 per 3.75 WIS"), else `value / divisor` per
## single point ("+20 per WIS", never "+1 per 0.05 WIS" — owner, #889). A
## non-positive value prints as itself.
func display_coefficient(value: float) -> float:
	if value <= 0.0:
		return value
	var step := _step(value)
	if step < 1.0 and not is_equal_approx(step, 1.0):
		return value / divisor
	return 1.0


## "20 STR" — or just "STR" at a step of 1, where the number is noise, and
## likewise below 1, where the coefficient side carries the rate. An
## authored [member per_phrase] still wins, for the rare ratio that wants
## bespoke wording.
func describe_per(value: float = 1.0) -> String:
	if not per_phrase.is_empty():
		return per_phrase
	var abbr := _abbrev(StatFormula.base_of(source_stat_id))
	var step := _step(value)
	if step < 1.0 or is_equal_approx(step, 1.0):
		return abbr
	return "%s %s" % [_trim(step), abbr]
