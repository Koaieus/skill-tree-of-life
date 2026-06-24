@tool
class_name ConstantField
extends ScalarField

@export var value: float = 1.0


func sample(_point: Vector2) -> float:
	return value
