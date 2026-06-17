@tool
extends Node2D

var _radius: float = 32.0
var _color: Color = Color.WHITE


func configure(r: float, color: Color) -> void:
	_radius = r
	_color = color
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius - 8.0, _color, true)
