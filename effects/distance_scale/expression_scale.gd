@tool
class_name ExpressionScale
extends DistanceScale

## An authored `(d, max, v) => value` formula, evaluated through Godot's
## [Expression]. The escape hatch that makes the closed-form library optional.
##
## Three float inputs, and it returns the value to grant:
##
## - [code]d[/code] — the metric's distance to this node.
## - [code]max[/code] — the reach bound in the same units, or `-1.0` unbounded.
## - [code]v[/code] — the authored value being shaped (the leaf modifier's
##   `value`). Per leaf, so a composite's three leaves get three results.
##
## [codeblock]
## "5 - d"               # 5 at the core, 4, 3, 2, 1 — the absolute ladder
## "v * (1 - d / max)"   # LinearScale
## "v"                   # FlatScale
## "v * d"               # ProportionalScale
## [/codeblock]
##
## [b]`v` is opt-in, and that is the point.[/b] A formula that omits it ignores
## the authored number entirely — which is how you say "heal 5, 4, 3, 2, 1"
## instead of "some fraction of 5". Mention it when you mean "scale what I
## authored". For a MULTIPLY or SET leaf the result is the factor / the set
## value itself — see [method EffectContext.grant_at].
##
## [b]Whether a result lands is [member AuraEffect.discard]'s call[/b], not
## this class's. `5 - d` over reach 5 computes a 0 at the rim; the default
## `NON_POSITIVE` drops it, `NEGATIVE` keeps it, `NONE` lets the ladder run on
## into negatives. The scale never second-guesses its own arithmetic.
##
## [b]Stateless like every other scale.[/b] `_expr` is compile state — one
## parsed [Expression] shared by every entity using this resource — never
## anything per-entity. Parsing is lazy and cached exactly as
## [ExpressionFormula] does it, and the [member formula] setter invalidates so
## an inspector hot-edit in the sandbox host takes effect immediately.

## The variable names bound at parse time, in the order [method scale] pushes
## their values — the INTERNAL spelling. Authors write `max`; see [constant BOUND].
const INPUTS := ["d", "__max", "v"]

## The authored name of the bound, and the internal one it is rewritten to.
##
## [b]`max` cannot be an [Expression] identifier.[/b] Godot's expression lexer
## reserves it for the built-in `max()` function, so `d / max` fails at PARSE
## with error 31, "Expected '('" — it is not a silent shadow, the formula simply
## never compiles. Verified empirically 2026-09-15; do not re-litigate by trying
## to pass "max" in the name list.
##
## The authored surface is worth more than the internal one, so [method _parse]
## rewrites `max` → `__max` on a word boundary instead of renaming the input.
## The boundary is what keeps `maxf(d, 1.0)` and `maxi` working — they are
## longer tokens, so `\bmax\b` does not touch them. `__` is the same
## separator the formula layer already uses for accessor tokens (#333), and it
## parses cleanly.
const BOUND_AUTHORED := "max"
const BOUND_INTERNAL := "__max"

@export_multiline var formula: String = "":
	set = _set_formula

## Null until first use, and null again after a parse failure — which is also
## the "already tried and failed" flag, so the error is pushed once per edit
## rather than once per node per recompute.
var _expr: Expression = null
var _parse_failed: bool = false


func _set_formula(v: String) -> void:
	formula = v
	_invalidate()


## The value to grant at [param distance]. Every input goes in as a **float**:
## [Expression] does integer division on ints, so an int-valued bound would make
## `d / max` floor to 0 or 1 and quietly flatten the whole curve (#333's sibling
## trap, verified in `test_inputs_are_floats_not_ints`).
func scale(distance: float, max_distance: float, value: float) -> float:
	if _expr == null:
		if _parse_failed:
			return 0.0
		_parse()
	if _expr == null:
		return 0.0
	var result: Variant = _expr.execute([float(distance), float(max_distance), float(value)])
	if _expr.has_execute_failed():
		push_error("ExpressionScale execute failed in '%s': %s" % [formula, _expr.get_error_text()])
		return 0.0
	return float(result)


## True whenever the formula actually reads the bound. #626's incremental
## topology path skips the bound (it passes -1.0, correct only for a
## bound-blind scale) and would otherwise serve stale values the moment
## membership moved the widest observed distance.
##
## Word-boundary matched, not a substring test: `maxf(d, 1)` names a function,
## not the input, and must not force a rebuild. Cheap enough to run per call —
## a hop-ball rebuild is the expensive side, and over-reporting only costs a
## rebuild while under-reporting is a correctness bug.
func uses_bound() -> bool:
	return _internal_text() != formula


## The authored formula with `max` rewritten to the identifier [Expression] will
## actually accept. Shared with [method uses_bound], so the two can never
## disagree about what counts as a mention of the bound.
func _internal_text() -> String:
	var rx := RegEx.create_from_string("\\b%s\\b" % BOUND_AUTHORED)
	if rx == null:
		return formula
	return rx.sub(formula, BOUND_INTERNAL, true)


func _invalidate() -> void:
	_expr = null
	_parse_failed = false


func _parse() -> void:
	var names := PackedStringArray(INPUTS)
	var ex := Expression.new()
	if ex.parse(_internal_text(), names) != OK:
		push_error("ExpressionScale parse error in '%s': %s" % [formula, ex.get_error_text()])
		_expr = null
		_parse_failed = true
		return
	_expr = ex
	_parse_failed = false
