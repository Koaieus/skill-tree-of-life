@tool
extends Node2D

const BORDER_WIDTH: float = 2.0
const FILL_ALPHA: float = 0.2

var _radius: float = 32.0
var _color: Color = Color.DIM_GRAY


func configure(r: float, color: Color) -> void:
	_radius = r
	_color = color
	queue_redraw()


func _draw() -> void:
	var fill := Color(_color.r, _color.g, _color.b, FILL_ALPHA)
	draw_circle(Vector2.ZERO, _radius, fill, true)
	draw_circle(Vector2.ZERO, _radius, _color, false, BORDER_WIDTH, true)
