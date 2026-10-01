@tool
class_name PlainRing
extends Indicator

## A static band ring hugging the wrapped boundary — the floor look every role
## without a richer marker mounts (via [code]themes/default.tres[/code]).
## Ring convention as [method SkillNode.ring_centerline]: [member
## ring_inner_offset] is the gap from the boundary to the band's INNER edge.

@export var ring_inner_offset: float = 4.5:
	set(value):
		ring_inner_offset = value
		_apply_geometry()
@export var ring_width: float = 3.0:
	set(value):
		ring_width = value
		_apply_geometry()


## Band centerline at the current stroke width; members place parts off it.
func ring_centerline() -> float:
	return SkillNode.ring_centerline(radius, ring_inner_offset, stroke(ring_width))


func _apply_geometry() -> void:
	var ring := get_node_or_null(^"%Ring") as IndicatorRingBand
	if ring != null:
		ring.width = stroke(ring_width)
		ring.centerline = ring_centerline()
