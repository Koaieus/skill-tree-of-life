class_name FoldTerms
extends RefCounted

## A resolved modifier pipeline: plain numbers, no boards, no stats. The
## value object [method ModifierBins.resolve] hands to whoever wants the
## merged pipeline (a readout, DebugClipboard) so nobody sums bins itself.
##
##   result = (base + add) × max(0, 1 + inc / 100) × mult + bon
##   or, when set_value != null, exactly set_value.
##
## Multipliers arrive already resolved against each source's own board —
## a formula-bound MULTIPLY has no meaning without one, so the resolution
## happens in [ModifierBins], never here.

var add: float = 0.0
var inc: float = 0.0
var bon: float = 0.0
var mult: float = 1.0
## The SET winner's effective value, or null when no SET applies.
var set_value: Variant = null


## Run the pipeline over [param base]; a SET winner wins outright.
func fold(base: float) -> float:
	if set_value != null:
		return set_value
	return arith(base, add, inc, bon, mult)


## The single scale the pipeline applies to (base + add): (1 + inc/100)
## clamped at 0, times the multiplier product.
func factor() -> float:
	return scale(inc, mult)


## The pipeline's arithmetic — the ONE definition, shared by [method fold]
## and the allocation-free [method ModifierBins.compute_single].
static func arith(base: float, add_: float, inc_: float, bon_: float, mult_: float) -> float:
	return (base + add_) * scale(inc_, mult_) + bon_


## Clamp (1 + Σ INCREASE/100) at 0: large stacks of negative INCREASE zero
## the stat out rather than flipping its sign. Net inc below -100% is a
## legitimate gameplay state (think "nerf modifier" pool entries on INT);
## the floor keeps the math predictable and the result interpretable as
## "× 0 + BONUS" for downstream consumers.
static func scale(inc_: float, mult_: float) -> float:
	return maxf(0.0, 1.0 + inc_ / 100.0) * mult_


## Render the pipeline over an authored base [param base_label]. Identity
## parts are omitted; a SET winner renders as "= N".
##   nothing        → "X"
##   add only       → "X+3" / "X−3"
##   inc only       → "X × 1.2"        (one factor, 2 decimals trimmed)
##   add + factor   → "(X+3) × 1.5"
##   + bonus        → "(X+3) × 1.5 + 2"
func describe(base_label: String = "X") -> String:
	if set_value != null:
		return "= %s" % _trim(float(set_value))
	var out := base_label
	if not is_zero_approx(add):
		out += _signed(add, "")
	var f := factor()
	var has_factor := not is_equal_approx(f, 1.0)
	if has_factor:
		if not is_zero_approx(add):
			out = "(%s)" % out
		out += " × %s" % _trim(f)
	if not is_zero_approx(bon):
		out += _signed(bon, " ")
	return out


## "+3" / "−3" (typographic minus), with [param gap] on both sides of the sign.
static func _signed(v: float, gap: String) -> String:
	var sign := "+" if v >= 0.0 else "−"
	return "%s%s%s%s" % [gap, sign, gap, _trim(absf(v))]


## Render a float without trailing zeros — whole values print as ints.
## Mirrors [method StatFormula._trim].
static func _trim(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	return ("%.2f" % v).trim_suffix("0")
