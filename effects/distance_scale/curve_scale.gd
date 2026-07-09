@tool
class_name CurveScale
extends DistanceScale

## Arbitrary shape, sampled at the normalized distance. The inspector-drawable
## escape hatch when none of the closed-form scales fit.
##
## Needs a bounded reach to normalize against; degrades to flat otherwise.
## Godot's Curve may range outside [0, 1], so this stays direction-agnostic too.

@export var curve: Curve = null

func scale(distance: float, max_distance: float) -> float:
	if curve == null:
		return 1.0
	if max_distance <= 0.0:
		return curve.sample(1.0)
	return curve.sample(clampf(distance / max_distance, 0.0, 1.0))
