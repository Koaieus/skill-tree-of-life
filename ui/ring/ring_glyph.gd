@tool
class_name RingGlyph
extends Node2D
## A plain disc or circle outline the [RingView] draws on its own display
## layer: the centre core's sigil and the selection marker. Presentation only.

@export var radius: float = 24.0:
	set(v):
		radius = v
		queue_redraw()
## Outline width in px; 0 draws a filled disc.
@export_range(0.0, 32.0, 0.5) var width: float = 0.0:
	set(v):
		width = v
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()


func _draw() -> void:
	if width <= 0.0:
		draw_circle(Vector2.ZERO, radius, color)
	else:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, width, true)
