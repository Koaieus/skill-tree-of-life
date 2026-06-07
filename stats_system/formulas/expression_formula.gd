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
## list DerivedModifierDef uses for dirty-tracking.

@export_multiline var formula: String = ""
@export var inputs: Array[StringName] = []

var _expr: Expression = null


func get_input_ids() -> Array[StringName]:
	return inputs


func compute(board: StatBoard) -> float:
	if _expr == null:
		_parse()
	if _expr == null:
		return 0.0
	var names := PackedStringArray()
	var values: Array = []
	for id in inputs:
		names.append(str(id))
		var s := board.get_stat(id)
		values.append(float(s.get_value()) if s != null else 0.0)
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
