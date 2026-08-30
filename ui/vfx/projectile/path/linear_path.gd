@tool
class_name LinearPath
extends ProjectilePath

## Straight line from origin to target. Maps to [constant PropagationEvent.Verb.EDGE]
## — travel along the graph edge. Also usable as a generic fallback path.


func evaluate(t: float, origin: Vector2, target: Vector2) -> Vector2:
	# Pace first, geometry second — [member ProjectilePath.ease_curve] remaps
	# TIME only, and defaults to the exact identity (#670).
	t = eased(t)
	return origin.lerp(target, t)
