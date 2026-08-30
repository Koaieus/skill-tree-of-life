@tool
class_name CubicBezierPath
extends ProjectilePath

## Cubic Bezier from origin → target with explicit launch and arrival
## tangents — the "forces or handles" feel without Curve2D's clunky
## point-and-handle editing.
##
## Knobs map to the Bezier control points:
##   P0 = origin
##   P1 = origin + start_tangent * (start_strength × origin→target distance)
##   P2 = target + end_tangent   * (end_strength   × origin→target distance)
##   P3 = target
##
## Strengths are FRACTIONS of distance so curve shape stays consistent across
## short and long shots. Tangents are direction vectors (normalised at eval):
## start_tangent is "which way it leaves the muzzle"; end_tangent is "which
## way it's coming IN from" — e.g. (0, -1) on both = comes down from above,
## the lobbed-mortar shape; perpendicular tangents = curveball; both at zero
## strength = straight line.

@export var start_tangent: Vector2 = Vector2(0.0, -1.0)
@export var start_strength: float = 0.5
@export var end_tangent: Vector2 = Vector2(0.0, -1.0)
@export var end_strength: float = 0.5


func evaluate(t: float, origin: Vector2, target: Vector2) -> Vector2:
	# Pace first, geometry second — [member ProjectilePath.ease_curve] remaps
	# TIME only, and defaults to the exact identity (#670).
	t = eased(t)
	var distance: float = origin.distance_to(target)
	var p1: Vector2 = origin + start_tangent.normalized() * (start_strength * distance)
	var p2: Vector2 = target + end_tangent.normalized() * (end_strength * distance)
	var u: float = 1.0 - t
	var uu: float = u * u
	var tt: float = t * t
	return uu * u * origin + 3.0 * uu * t * p1 + 3.0 * u * tt * p2 + tt * t * target
