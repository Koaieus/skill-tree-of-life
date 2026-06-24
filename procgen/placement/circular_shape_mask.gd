@tool
class_name CircularShapeMask
extends ShapeMask

## Disk centred at (0, 0). With `auto_scale = true`, `radius` is overwritten
## by [GraphProcgen] before Poisson runs to fit the requested node count;
## set false to honour the inspector value verbatim.

@export var radius: float = 600.0


func contains(point: Vector2) -> bool:
	return point.length_squared() <= radius * radius


func aabb() -> Rect2:
	return Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0))


func size_for(target_area: float, min_dimension: float = 100.0) -> void:
	# π · r² = target_area  →  r = sqrt(target_area / π).
	var r := sqrt(maxf(0.0, target_area) / PI)
	radius = maxf(r, min_dimension)
