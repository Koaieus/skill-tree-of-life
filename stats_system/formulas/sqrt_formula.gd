@tool
class_name SqrtFormula
extends StatFormula

## The transfer function from a runaway source stat into a damage-like target
## that must stay legible from small values to a "fun to have a runaway stat"
## extreme (#760: 20k INT was hit at the 2026-09-06 LAN and is intentional —
## the owner call was that the SCALING into spell damage was off, not the
## stat itself).
##
## `f(source) = floor( sqrt(max(source, 0)) / divisor )`
##
## [b]Replaces [code]KneeSqrtFormula[/code] (#776 amendment, 2026-09-13).[/b]
## The linear-below-a-knee blend is gone — owner: "the knee is not intuitive.
## possibly we drop it in favor of a pure sqrt relationship." Early game is
## therefore NOT byte-identical to a [RatioFormula] any more (the knee's
## below-knee branch used to guarantee that); at `divisor = 1`, INT 10 → 3,
## 100 → 10, 500 → 22, 1k → 32, 5k → 71, 20k → 141.
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
## `divisor` is an `@export` starting value, not a tuned constant — it is the
## owner's to retune post-acceptance (#776). Ship the shape; don't chase a
## bullet by moving it.

## The stat being scaled. Same accessor-token convention as [RatioFormula].
@export var source_stat_id: StringName = &""

## Divides the sqrt'd source. `1` reads "√INT"; anything else reads
## "N √INT".
@export var divisor: float = 10.0


func to_dict() -> Dictionary:
	var d := super()
	d["type"] = StatModifierCodec.TAG_SQRT
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
		push_error("SqrtFormula: divisor is 0 for source '%s'" % source_stat_id)
		return 0.0
	var s := board.get_stat(StatFormula.base_of(source_stat_id))
	if s == null:
		return 0.0
	var v: Variant = s.read_accessor(StatFormula.accessor_of(source_stat_id))
	var source := maxf(0.0, float(v))
	return floorf(sqrt(source) / divisor)


## "√INT" at divisor 1, else "20 √INT" — never a bare "20 INT", which would
## misdescribe this as a linear rate (the #773 class of lie). An authored
## [member per_phrase] still wins. The base [method describe_clause] wraps
## this in " per %s", so the rendered clause reads " per 20 √INT" — honest,
## since that IS the rule, unlike a bare "per N INT" would be.
func describe_per() -> String:
	if not per_phrase.is_empty():
		return per_phrase
	var abbr := _abbrev(StatFormula.base_of(source_stat_id))
	if is_equal_approx(divisor, 1.0):
		return "√%s" % abbr
	return "%s √%s" % [_trim(divisor), abbr]
