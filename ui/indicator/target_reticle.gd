@tool
class_name TargetReticle
extends Indicator

## The aim-point reticle: a static band ring plus a spinning crosshair outside
## it. Every offset is relative to [member Indicator.radius], so it grows with
## the wrapped node. The spin is its own — [member %Spinner]'s rotation advances
## in [method _process]; nothing outside redraws per frame.

## Gap from the wrapped boundary to the ring's INNER edge. Past 8 it clears
## the hover glow band (radius..+8).
@export var ring_inner_offset: float = 9.0:
	set(value):
		ring_inner_offset = value
		_apply_geometry()
@export var ring_width: float = 4.0:
	set(value):
		ring_width = value
		_apply_geometry()
@export var arm_count: int = 4:
	set(value):
		arm_count = value
		_apply_geometry()
## Gap from the wrapped boundary to each arm's inner tip.
@export var arm_inner_offset: float = 15.0:
	set(value):
		arm_inner_offset = value
		_apply_geometry()
@export var arm_length: float = 8.0:
	set(value):
		arm_length = value
		_apply_geometry()
@export var arm_width: float = 3.0:
	set(value):
		arm_width = value
		_apply_geometry()
## 0 = static.
@export var spin_degrees_per_second: float = 45.0


func _process(delta: float) -> void:
	if spin_degrees_per_second == 0.0:
		return
	var spinner := get_node_or_null(^"%Spinner") as Node2D
	if spinner != null:
		spinner.rotation = wrapf(spinner.rotation + deg_to_rad(spin_degrees_per_second) * delta, -PI, PI)


func _apply_geometry() -> void:
	var ring := get_node_or_null(^"%Ring") as IndicatorRingBand
	if ring != null:
		ring.width = ring_width
		ring.centerline = SkillNode.ring_centerline(radius, ring_inner_offset, ring_width)
	var arms := get_node_or_null(^"%Spinner") as IndicatorCrosshairArms
	if arms != null:
		arms.arm_count = arm_count
		arms.inner_radius = radius + arm_inner_offset
		arms.arm_length = arm_length
		arms.arm_width = arm_width
