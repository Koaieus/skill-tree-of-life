@tool
class_name IndicatorCrosshairArms
extends Node2D

## [member arm_count] white radial strokes, evenly spaced, each spanning
## [member inner_radius]..[member inner_radius] + [member arm_length] — an
## indicator part. Its owner pushes every value (radii already absolute) and
## may spin this node; the tint arrives through the inherited modulate.

@export var arm_count: int = 4:
	set(value):
		arm_count = value
		queue_redraw()
@export var inner_radius: float = 0.0:
	set(value):
		inner_radius = value
		queue_redraw()
@export var arm_length: float = 8.0:
	set(value):
		arm_length = value
		queue_redraw()
@export var arm_width: float = 3.0:
	set(value):
		arm_width = value
		queue_redraw()


func _draw() -> void:
	if arm_count <= 0 or arm_length <= 0.0:
		return
	for i in arm_count:
		var dir := Vector2.from_angle(TAU * float(i) / float(arm_count))
		draw_line(dir * inner_radius, dir * (inner_radius + arm_length), Color.WHITE, arm_width, true)
