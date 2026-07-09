@tool
class_name LinearScale
extends DistanceScale

## Normalized ramp across the reach bound, clamped to [0, 1].
##
## Requires a bounded reach — with `max_distance <= 0` there is no domain to
## normalize against, so it degrades to flat rather than dividing by zero. If you
## want a scale that grows without bound, you want [ProportionalScale].

## Falling by default (strongest at the source). Set to rise toward the rim.
@export var rising: bool = false

func scale(distance: float, max_distance: float) -> float:
	if max_distance <= 0.0:
		return 1.0
	var t: float = clampf(distance / max_distance, 0.0, 1.0)
	return t if rising else 1.0 - t
