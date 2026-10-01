@tool
class_name HiltMarker
extends Indicator

## The melee pivot: a thick band ring plus a two-bar crossguard that lies
## across the blade — [member %Guard] rotates to [code]facing.angle() + PI/2[/code],
## so its bars run perpendicular to the direction the blade extends. With no
## facing the guard sits at its unrotated +PI/2.

## Gap from the wrapped boundary to the ring's INNER edge.
@export var ring_inner_offset: float = 9.0:
	set(value):
		ring_inner_offset = value
		_apply_geometry()
@export var ring_width: float = 4.0:
	set(value):
		ring_width = value
		_apply_geometry()
## Gap from the wrapped boundary to each guard bar's inner tip.
@export var guard_inner_offset: float = 9.0:
	set(value):
		guard_inner_offset = value
		_apply_geometry()
@export var guard_length: float = 10.0:
	set(value):
		guard_length = value
		_apply_geometry()
@export var guard_width: float = 3.0:
	set(value):
		guard_width = value
		_apply_geometry()


func _apply_geometry() -> void:
	var ring := get_node_or_null(^"%Ring") as IndicatorRingBand
	if ring != null:
		var w := stroke(ring_width)
		ring.width = w
		ring.centerline = SkillNode.ring_centerline(radius, ring_inner_offset, w)
	var guard := get_node_or_null(^"%Guard") as IndicatorCrosshairArms
	if guard != null:
		guard.arm_count = 2
		guard.inner_radius = radius + guard_inner_offset
		guard.arm_length = guard_length
		guard.arm_width = stroke(guard_width)
		guard.rotation = facing.angle() + PI / 2.0
