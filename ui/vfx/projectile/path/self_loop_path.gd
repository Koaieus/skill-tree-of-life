@tool
class_name SelfLoopPath
extends ProjectilePath

## Leave-and-return arc for [constant PropagationEvent.Verb.SELF_LOOP] events
## (origin == target; a straight lerp is degenerate).
##
## Draws a cubic Bezier that arcs out from origin along [member loop_direction],
## reaches an apex, and returns. The control-point placement produces a
## teardrop-like shape.

## Pixels the apex sits above the origin.
@export var loop_height: float = 200.0
## Horizontal spread — half-width in each direction from origin.
@export var loop_width: float = 80.0
## Unit vector the loop arcs toward (default: world-up).
@export var loop_direction: Vector2 = Vector2(0.0, -1.0)


func evaluate(t: float, origin: Vector2, _target: Vector2) -> Vector2:
	var up := loop_direction.normalized()
	var right := Vector2(up.y, -up.x)

	var p0 := origin
	var p1 := origin + right * loop_width + up * loop_height * 0.25
	var p2 := origin - right * loop_width + up * loop_height * 1.1
	var p3 := origin

	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3
