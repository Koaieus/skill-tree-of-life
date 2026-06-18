@tool
class_name CircularShapeMask
extends ShapeMask

@export var radius: float = 600.0


func contains(point: Vector2) -> bool:
	return point.length_squared() <= radius * radius


func aabb() -> Rect2:
	return Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0))
