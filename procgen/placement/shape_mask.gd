@tool
class_name ShapeMask
extends Resource

## Region within which procgen samples node positions. Subclass to add shapes
## (circle, rect, annulus, polygon). Coordinates are graph-local; (0,0) is the
## centre of the generated world.
##
## **Sizing model.** A ShapeMask carries PROPORTIONS, not absolute dimensions.
## When `auto_scale` is true (the default), [GraphProcgen] sizes the mask at
## generate-time so it can comfortably hold `node_count` points at the
## requested `min_dist` — preventing the "capsule artifact" where the mask is
## too small for the requested count and Poisson under-fills. Set
## `auto_scale = false` to use the inspector-edited dimensions verbatim (e.g.
## hand-tuned level shapes).

## When true (default), [GraphProcgen] calls [method size_for] before Poisson
## with the area required for `node_count × min_dist²` plus a safety margin.
## When false, the shape's inspector dimensions are used as-is.
@export var auto_scale: bool = true


func contains(_point: Vector2) -> bool:
	return true

## Axis-aligned bounds used by the Poisson sampler to seed rejection sampling.
func aabb() -> Rect2:
	return Rect2()


## Scales the shape to contain at least `target_area` square units while
## preserving proportions. Subclasses override; base no-op for shapes that
## have no scale parameter. `min_dimension` is a soft floor — small node
## counts shouldn't collapse the mask below something workable.
func size_for(_target_area: float, _min_dimension: float = 100.0) -> void:
	pass
