@tool
extends Node2D

const BORDER_WIDTH: float = 2.0
const FILL_ALPHA: float = 0.7

var _radius: float = 32.0
var _is_pivot: bool = false


func configure(r: float, pivot: bool) -> void:
	_radius = r
	_is_pivot = pivot
	queue_redraw()


func _draw() -> void:
	var color := Color.FIREBRICK if not _is_pivot else Color.CHOCOLATE
	var fill := Color(color.r, color.g, color.b, FILL_ALPHA)
	draw_circle(Vector2.ZERO, _radius, fill, true)
	draw_circle(Vector2.ZERO, _radius, color, false, BORDER_WIDTH, true)
