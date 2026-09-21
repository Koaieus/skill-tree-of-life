@tool
class_name TableScale
extends DistanceScale

## Stub — see the red test.

enum PastEnd { NOT_GRANTED, HOLD_LAST }

@export var per_step: Array[float] = []
@export var past_end: PastEnd = PastEnd.NOT_GRANTED


func scale(_distance: float, _max_distance: float, _value: float) -> float:
	return 0.0
