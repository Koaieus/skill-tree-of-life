@tool
class_name RangeRing
extends Node2D

## Visual for a single Euclidean reach ring. Live-tweakable in the editor —
## drop a scene that inherits this and override colours / line widths to
## specialize without touching the finder or overlay code.

@export var radius: float = 0.0:
	set(value):
		radius = value
		queue_redraw()

@export var color: Color = Color(1.0, 0.85, 0.0, 0.30):
	set(value):
		color = value
		queue_redraw()

@export var line_width: float = 1.5:
	set(value):
		line_width = value
		queue_redraw()

@export_range(8, 256, 1) var segments: int = 64:
	set(value):
		segments = value
		queue_redraw()


func configure(p_position: Vector2, p_radius: float) -> void:
	position = p_position
	radius = p_radius


func _draw() -> void:
	if radius <= 0.0:
		return
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, segments, color, line_width)
