@tool
class_name IndicatorChevronFan
extends Node2D

## [member count] white chevrons fanned across [member spread_deg], centred on
## this node's +x and pointing outward, each centred [member mid_radius] from
## the origin — an indicator part. Its owner pushes every value (radii already
## absolute) and rotates this node to aim; the tint arrives through the
## inherited modulate. [member hollow] draws outlines of [member outline_width].

@export var count: int = 3:
	set(value):
		count = value
		queue_redraw()
@export var spread_deg: float = 50.0:
	set(value):
		spread_deg = value
		queue_redraw()
@export var size: float = 7.0:
	set(value):
		size = value
		queue_redraw()
@export var mid_radius: float = 0.0:
	set(value):
		mid_radius = value
		queue_redraw()
@export var hollow: bool = false:
	set(value):
		hollow = value
		queue_redraw()
@export var outline_width: float = 1.6:
	set(value):
		outline_width = value
		queue_redraw()


func _draw() -> void:
	if count <= 0 or size <= 0.0 or mid_radius <= 0.0:
		return
	var half := size * 0.5
	var spread := deg_to_rad(spread_deg)
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = spread * (float(i) / float(count - 1) - 0.5)
		var d := Vector2.from_angle(offset)
		var side := d.orthogonal() * half
		var tip := d * (mid_radius + half)
		var back := d * (mid_radius - half)
		var notch := d * (mid_radius - half * 0.3)
		var points := PackedVector2Array([tip, back + side, notch, back - side])
		if hollow:
			points.append(tip)
			draw_polyline(points, Color.WHITE, outline_width, true)
		else:
			draw_colored_polygon(points, Color.WHITE)
