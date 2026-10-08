@tool
class_name AimShapeVisual
extends Node2D

## Visual for an aimed spell's shape ([RangeVisual.AimEntry]): a [LineShape]
## draws as its band (rounded at the far end, the capsule its hit test uses),
## a [ConeShape] as its sector. Drawn to the full reach length, through fog —
## the predicted hits, not the shape, are what fog hides.

@export var color: Color = Color(1.0, 0.85, 0.0, 0.45):
	set(value):
		color = value
		queue_redraw()

@export var fill_color: Color = Color(1.0, 0.85, 0.0, 0.10):
	set(value):
		fill_color = value
		queue_redraw()

@export var line_width: float = 1.5:
	set(value):
		line_width = value
		queue_redraw()

@export_range(4, 64, 1) var arc_segments: int = 16:
	set(value):
		arc_segments = value
		queue_redraw()

var angle: float = 0.0
var length: float = 0.0
var shape: AimShape = null


func configure(p_position: Vector2, p_angle: float, p_length: float, p_shape: AimShape) -> void:
	position = p_position
	angle = p_angle
	length = p_length
	shape = p_shape
	queue_redraw()


## The outline, in this node's local space, of [param p_shape] pointed at
## [param p_angle] out to [param p_length]; empty for an unknown shape.
func outline(p_shape: AimShape, p_angle: float, p_length: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if p_length <= 0.0:
		return pts
	if p_shape is LineShape:
		var w := (p_shape as LineShape).width
		var dir := Vector2.from_angle(p_angle)
		var side := dir.orthogonal() * w
		pts.append(side)
		pts.append(dir * p_length + side)
		# The far cap: a half circle from one side to the other.
		for i in range(1, arc_segments):
			var a := p_angle + PI / 2.0 - PI * i / arc_segments
			pts.append(dir * p_length + Vector2.from_angle(a) * w)
		pts.append(dir * p_length - side)
		pts.append(-side)
	elif p_shape is ConeShape:
		var half := deg_to_rad((p_shape as ConeShape).half_angle_deg)
		pts.append(Vector2.ZERO)
		for i in arc_segments + 1:
			pts.append(Vector2.from_angle(p_angle - half + 2.0 * half * i / arc_segments) * p_length)
	return pts


func _draw() -> void:
	var pts := outline(shape, angle, length)
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_color)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, color, line_width, true)
