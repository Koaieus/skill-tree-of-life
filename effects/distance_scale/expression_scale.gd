@tool
class_name ExpressionScale
extends DistanceScale

## An authored `(d, max, v) => value` formula, evaluated through Godot's
## [Expression]. The escape hatch that makes the closed-form library optional.
##
## STUB — #900 red phase.

@export_multiline var formula: String = "":
	set(v):
		formula = v
		_invalidate()

var _expr: Expression = null


func scale(_distance: float, _max_distance: float, _value: float) -> float:
	return 0.0


func uses_bound() -> bool:
	return false


func _invalidate() -> void:
	_expr = null
