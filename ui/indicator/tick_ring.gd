@tool
class_name TickRing
extends PlainRing

## A thin [PlainRing] with [member tick_count] short static radial ticks
## standing just outside it.

@export var tick_count: int = 4:
	set(value):
		tick_count = value
		_apply_geometry()
@export var tick_length: float = 5.0:
	set(value):
		tick_length = value
		_apply_geometry()


func _apply_geometry() -> void:
	super()
	var ticks := get_node_or_null(^"%Ticks") as IndicatorCrosshairArms
	if ticks != null:
		var w := stroke(ring_width)
		ticks.arm_count = tick_count
		ticks.inner_radius = ring_centerline() + w * 0.5
		ticks.arm_length = tick_length
		ticks.arm_width = w
