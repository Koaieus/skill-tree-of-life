@tool
class_name KneeSqrtFormula
extends StatFormula

## Linear below a knee, sqrt above it (#760) — the transfer function from a
## runaway source stat into a damage-like target that must stay legible from
## small values to a "fun to have a runaway stat" extreme (20k INT was hit at
## the 2026-09-06 LAN and is intentional; the owner call was that the SCALING
## into spell damage was off, not the stat itself).
##
## `f(source) = floor( min(source, sqrt(knee * source)) / divisor )`
##
## [b]`min` is the whole trick[/b]: below the knee `sqrt(knee * source) >
## source`, so the linear branch wins and this is byte-identical to
## [RatioFormula]; above it the geometric mean wins and compresses. The two
## branches agree exactly at `source == knee`, so the curve is continuous by
## construction — there is no branch boundary to get wrong.
##
## [b]Only `sqrt` — never `log`/`exp`/`pow`.[/b] `log` was already tried and
## reverted once (#547, mana-per-turn): every platform's libm rounds it
## differently in the last bits, and derived stats are recomputed on EVERY
## PEER rather than sent over the wire, so a Windows client and a Linux host
## would silently disagree. IEEE 754 requires `sqrt` to be correctly rounded,
## so it has no such failure mode. See
## `docs/domain/multiplayer-sync-model.md:126-142`.
##
## [b]Guard[/b]: the source is clamped to `maxf(0.0, source)` before the sqrt
## — a negative source would otherwise be `sqrt(NaN)` and poison the board.
##
## `knee` and `divisor` are `@export` starting values, not tuned constants —
## they are the owner's to retune post-acceptance (#760). Ship the shape;
## don't chase a bullet by moving these.

## The stat being scaled. Same accessor-token convention as [RatioFormula].
@export var source_stat_id: StringName = &""

## Points of `source_stat_id` per step, below AND above the knee — this is
## the same divisor the linear branch used before this formula existed, kept
## so the below-knee output is unchanged to the bit.
@export var divisor: float = 10.0

## The source value at which the curve bends from linear to sqrt. Below this,
## `f` is exactly `RatioFormula(source_stat_id, divisor)`; above it, `f` grows
## with `sqrt(source)` instead of `source`.
@export var knee: float = 500.0


func to_dict() -> Dictionary:
	var d := super()
	d["type"] = StatModifierCodec.TAG_KNEE_SQRT
	d["source_stat_id"] = source_stat_id
	d["divisor"] = divisor
	d["knee"] = knee
	return d


func read_dict(d: Dictionary) -> void:
	super(d)
	source_stat_id = StringName(d.get("source_stat_id", &""))
	divisor = float(d.get("divisor", 10.0))
	knee = float(d.get("knee", 500.0))


func get_input_ids() -> Array[StringName]:
	return [StatFormula.base_of(source_stat_id)]


func compute(board: StatBoard) -> float:
	if is_zero_approx(divisor):
		push_error("KneeSqrtFormula: divisor is 0 for source '%s'" % source_stat_id)
		return 0.0
	var s := board.get_stat(StatFormula.base_of(source_stat_id))
	if s == null:
		return 0.0
	var v: Variant = s.read_accessor(StatFormula.accessor_of(source_stat_id))
	var source := maxf(0.0, float(v))
	var linear := source
	var geometric := sqrt(knee * source)
	return floorf(minf(linear, geometric) / divisor)


## "10 INT" below the knee — the same generated phrase [RatioFormula] would
## produce, since that IS this formula's behaviour under the knee. An
## authored [member per_phrase] still wins.
func describe_per() -> String:
	if not per_phrase.is_empty():
		return per_phrase
	var abbr := _abbrev(StatFormula.base_of(source_stat_id))
	if is_equal_approx(divisor, 1.0):
		return abbr
	return "%s %s" % [_trim(divisor), abbr]


## Overrides [StatFormula.describe_clause] — wrapping [method describe_per]'s
## "10 INT" in " per " would be honest below the knee and a lie above it, so
## this shape gets its own clause naming the bend, same precedent as
## [ThresholdFormula] (#773).
func describe_clause() -> String:
	if not per_phrase.is_empty():
		return super()
	var abbr := _abbrev(StatFormula.base_of(source_stat_id))
	return " scaling with %s, with diminishing returns past %s %s" % [
		abbr, _trim(knee), abbr
	]
