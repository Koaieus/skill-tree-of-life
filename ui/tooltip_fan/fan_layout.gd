class_name FanLayout
extends RefCounted

## Pure rect relaxation solver for the tooltip fan: N bodies spring toward
## authored rests while position projection keeps them apart from each
## other, from fixed obstacles, and inside a keep-in rect. No nodes; the
## driver feeds bodies in and reads `position` back.


class Body extends RefCounted:
	var size: Vector2
	var rest: Vector2
	var position: Vector2
	var velocity: Vector2


static func step(_bodies: Array[FanLayout.Body], _obstacles: Array[Rect2], _keep_in: Rect2,
		_params: Dictionary, _dt: float) -> float:
	return 0.0


static func settle(_bodies: Array[FanLayout.Body], _obstacles: Array[Rect2], _keep_in: Rect2,
		_params: Dictionary, _max_steps := 600, _epsilon := 0.05) -> int:
	return -1
