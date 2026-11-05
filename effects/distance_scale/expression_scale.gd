@tool
class_name ExpressionScale
extends DistanceScale

## An authored `(d, max, v, h, e, rel) => value` formula run through Godot's
## `Expression`. NaN means "grant nothing"; 0 is a value. `h`/`e` are computed only
## when named; the 3-arg `scale` path feeds sentinels. `AuraEffect.discard` decides
## whether a result lands. Stateless: the parsed `_expr` is shared compile state.
## See docs/domain/effect-system.md

## The variable names bound at parse time, in the order [method scale] pushes
## their values — the INTERNAL spelling. Authors write `max`; see [constant BOUND].
const INPUTS := ["d", "__max", "v", "h", "e", "rel"]

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
## Memoized [method _internal_text] and [method _mentions] answers — the regex
## work behind `uses_bound` / `wants_hops` / `wants_euclid`, which
## [AuraEffect] asks per grant pass and per node. Cleared with the parse on
## every formula edit, so a hot-edit is never served a stale answer.
var _internal_cache: String = ""
var _internal_cached: bool = false
var _mentions_cache: Dictionary[String, bool] = {}


func _set_formula(v: String) -> void:
	formula = v
	_invalidate()


## The value to grant at [param distance]. Every input goes in as a **float**:
## [Expression] does integer division on ints, so an int-valued bound would make
## `d / max` floor to 0 or 1 and quietly flatten the whole curve (#333's sibling
## trap, verified in `test_inputs_are_floats_not_ints`).
func scale(distance: float, max_distance: float, value: float) -> float:
	return scale_at(distance, max_distance, value, -1.0, -1.0, 0)


## The six-input door — see the class docs for what each input is. [param
## relation] stays an int: it is a bit, never divided.
func scale_at(distance: float, max_distance: float, value: float,
		hops: float, euclid: float, relation: int) -> float:
	if _expr == null:
		if _parse_failed:
			return 0.0
		_parse()
	if _expr == null:
		return 0.0
	var result: Variant = _expr.execute([
		float(distance), float(max_distance), float(value), float(hops), float(euclid), int(relation),
	])
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


## Whether the formula names `h` — word-boundary matched, like
## [method uses_bound], so `hypot(d, 1)` does not trigger a hop walk.
func wants_hops() -> bool:
	return _mentions("h")


## Whether the formula names `e`. `1e5` is one token to `\b`, so a literal
## exponent does not count.
func wants_euclid() -> bool:
	return _mentions("e")


## Worth memoising unless the formula reads continuous `e`.
func memoizable() -> bool:
	return not wants_euclid()


func _mentions(input: String) -> bool:
	if _mentions_cache.has(input):
		return _mentions_cache[input]
	var rx := RegEx.create_from_string("\\b%s\\b" % input)
	var hit := rx != null and rx.search(_internal_text()) != null
	_mentions_cache[input] = hit
	return hit


## The authored formula with `max` rewritten to the identifier [Expression] will
## actually accept. Shared with [method uses_bound], so the two can never
## disagree about what counts as a mention of the bound.
func _internal_text() -> String:
	if _internal_cached:
		return _internal_cache
	var rx := RegEx.create_from_string("\\b%s\\b" % BOUND_AUTHORED)
	_internal_cache = formula if rx == null else rx.sub(formula, BOUND_INTERNAL, true)
	_internal_cached = true
	return _internal_cache


func _invalidate() -> void:
	_expr = null
	_parse_failed = false
	_internal_cached = false
	_internal_cache = ""
	_mentions_cache.clear()


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
