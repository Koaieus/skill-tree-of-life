@tool
class_name ShapeMask
extends Resource

## Region within which procgen samples node positions. Subclass to add shapes
## (circle, rect, annulus, polygon). Coordinates are graph-local; (0,0) is the
## centre of the generated world.

func contains(_point: Vector2) -> bool:
	return true

## Axis-aligned bounds used by the Poisson sampler to seed rejection sampling.
func aabb() -> Rect2:
	return Rect2()
