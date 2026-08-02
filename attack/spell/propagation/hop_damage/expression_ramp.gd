@tool
class_name ExpressionRamp
extends HopDamage

## One-off escape hatch: author a float-returning GDScript [Expression]
## inline on the spell .tres. Mirrors [ExpressionFilter] and the
## [ExpressionFormula] pattern in the stats system.
##
## Available identifiers:
##   damage     — float, the parent's damage (already scaled by prior hops).
##   hop_index  — int,   the parent's hop_index (0 at the seed).

@export_multiline var expression: String = "damage"

var _expr: Expression = null
var _last_text: String = ""


func apply(damage: float, hop_index: int) -> float:
	if _expr == null or _last_text != expression:
		_expr = Expression.new()
		var err := _expr.parse(expression, ["damage", "hop_index"])
		if err != OK:
			push_warning("ExpressionRamp parse error: %s" % _expr.get_error_text())
			_expr = null
			return damage
		_last_text = expression
	var result: Variant = _expr.execute([damage, hop_index], null, false)
	if _expr.has_execute_failed():
		return damage
	return float(result)


func get_description() -> String:
	return "ramp: %s" % expression