@tool
extends Node2D
## One filled circle — the "snapshot" of a node's inner disk that the alloc
## spike and the dealloc lift both carry. A texture swap later replaces `_draw`
## with a Sprite2D; keep `disk_radius` / `disk_color` and every caller holds.

@export_range(1.0, 128.0, 0.5) var disk_radius: float = 16.0:
	set(value):
		disk_radius = maxf(1.0, value)
		queue_redraw()

## A setter, so `tween_property("disk_color", ...)` repaints every frame.
@export var disk_color: Color = Color.WHITE:
	set(value):
		disk_color = value
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, disk_radius, disk_color, true)
