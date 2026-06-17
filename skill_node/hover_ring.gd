@tool
extends Node2D

@export var color: Color = Color.YELLOW_GREEN

var _radius: float = 32.0


func configure(r: float) -> void:
	_radius = r
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius + 6.0, color, false, 3.0)
