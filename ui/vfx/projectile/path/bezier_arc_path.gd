class_name BezierArcPath
extends ProjectilePath

## Quadratic Bezier through `origin → apex → target`, with the apex at the
## segment midpoint lifted `apex_height` pixels along [member apex_direction]
## (default: world-up). The original `RangedTracer` arc, made tunable.

## Pixels along [member apex_direction] the apex sits from the segment midpoint.
@export var apex_height: float = 420.0
## Unit vector the apex is lifted along. Default (0,-1) = scene-up.
@export var apex_direction: Vector2 = Vector2(0.0, -1.0)


func evaluate(t: float, origin: Vector2, target: Vector2) -> Vector2:
	var mid := origin.lerp(target, 0.5)
	var apex := mid + apex_direction.normalized() * apex_height
	var u := 1.0 - t
	return u * u * origin + 2.0 * u * t * apex + t * t * target
