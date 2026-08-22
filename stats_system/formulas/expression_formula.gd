@tool
class_name ExpressionFormula
extends StatFormula

## Arbitrary formula using Godot's Expression evaluator.
## Variable names in the formula string must match the StringNames in `inputs`.
##
## Example:
##   formula = "floor(strength / 10.0) * dexterity * 0.05"
##   inputs  = [&"strength", &"dexterity"]
##
## The Expression is parsed once on first compute() and cached. If the formula
## string changes at runtime (editor @tool use), call _invalidate() to reparse.
## `inputs` must list every stat the formula reads — this is also the subscription
## list DerivedStatModifier uses for dirty-tracking.
##
## [member inputs] accept bare `<stat_id>` (reads the computed value / cap) or
## `<stat_id>__<accessor>` tokens (read a named accessor via [method
## Stat.read_accessor]). The variable name in the expression text is the full
## (decorated) token — e.g. `health__current + 1` with `inputs = [&"health__current"]`.
## The engine parses and executes `__`-separated names correctly (see #333);
## dependency tracking strips to the base id via [method StatFormula.base_of].

@export_multiline var formula: String = ""
@export var inputs: Array[StringName] = []

var _expr: Expression = null


## `_expr` is deliberately NOT part of the wire form: [method compute] parses
## lazily on first read (`if _expr == null: _parse()`), so a decoded instance
## compiles itself the first time anyone asks it for a value.
func to_dict() -> Dictionary:
	var d := super()
	d["type"] = StatModifierCodec.TAG_EXPRESSION
	d["formula"] = formula
	var ids: Array = []
	for input_id in inputs:
		ids.append(String(input_id))
	d["inputs"] = ids
	return d


func read_dict(d: Dictionary) -> void:
	super(d)
	formula = String(d.get("formula", ""))
	var ids: Array[StringName] = []
	for raw in (d.get("inputs", []) as Array):
		ids.append(StringName(raw))
	inputs = ids
	_invalidate()


func get_input_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.resize(inputs.size())
	for i in inputs.size():
		out[i] = StatFormula.base_of(inputs[i])
	return out


func compute(board: StatBoard) -> float:
	if _expr == null:
		_parse()
	if _expr == null:
		return 0.0
	var names := PackedStringArray()
	var values: Array = []
	for id in inputs:
		names.append(str(id))
		var s := board.get_stat(StatFormula.base_of(id))
		if s == null:
			values.append(0.0)
		else:
			values.append(float(s.read_accessor(StatFormula.accessor_of(id))))
	var result = _expr.execute(values)
	if _expr.has_execute_failed():
		push_error("ExpressionFormula execute failed in '%s': %s" % [formula, _expr.get_error_text()])
		return 0.0
	return float(result)


func _invalidate() -> void:
	_expr = null


func _parse() -> void:
	var names := PackedStringArray()
	for id in inputs:
		names.append(str(id))
	_expr = Expression.new()
	if _expr.parse(formula, names) != OK:
		push_error("ExpressionFormula parse error in '%s': %s" % [formula, _expr.get_error_text()])
		_expr = null


# --- Static tooling helpers ----------------------------------------------
#
# Godot's `Expression` class has no AST introspection — it accepts a name
# list at parse time but won't tell you which names a parsed expression
# actually references. So tooling that wants to derive `inputs` from
# `formula` has to string-match. We pair two helpers:
#
#   validate(text, candidates) — uses `Expression.parse(text, candidates)`
#     to catch syntax errors and unknown identifiers. Pass every stat id
#     you'd allow as a candidate so a valid formula parses.
#
#   detect_inputs(text, candidates) — word-boundary matches each candidate
#     against the formula text and returns the subset actually used. This
#     is what feeds the `inputs` field, replacing manual entry that gets
#     forgotten and silently breaks subscription.

## Returns "" on parse success, or the Expression's error text.
static func validate(formula_text: String, candidate_ids: Array) -> String:
	if formula_text.strip_edges() == "":
		return "formula is empty"
	var names := PackedStringArray()
	for id in candidate_ids:
		names.append(str(id))
	var ex := Expression.new()
	if ex.parse(formula_text, names) != OK:
		return ex.get_error_text()
	return ""


## Returns the subset of `candidate_ids` that appear as whole-word tokens
## in `formula_text`. Order follows `candidate_ids` for stable output.
static func detect_inputs(formula_text: String, candidate_ids: Array) -> Array[StringName]:
	var found: Array[StringName] = []
	for id in candidate_ids:
		var rx := RegEx.create_from_string("\\b%s\\b" % str(id))
		if rx != null and rx.search(formula_text) != null:
			found.append(id)
	return found
