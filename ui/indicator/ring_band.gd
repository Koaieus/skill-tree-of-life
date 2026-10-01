@tool
class_name IndicatorRingBand
extends Node2D

## A static white stroke at [member centerline] — an indicator part. Its owner
## pushes both values; the tint arrives through the inherited modulate.

@export var centerline: float = 0.0:
	set(value):
		centerline = value
		queue_redraw()
@export var width: float = 4.0:
	set(value):
		width = value
		queue_redraw()
@export var segments: int = 48:
	set(value):
		segments = value
		queue_redraw()


func _draw() -> void:
	if centerline <= 0.0 or width <= 0.0:
		return
	draw_arc(Vector2.ZERO, centerline, 0.0, TAU, segments, Color.WHITE, width, true)
