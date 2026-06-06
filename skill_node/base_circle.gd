@tool
extends Node2D

const BORDER_WIDTH: float = 2.0
const FILL_ALPHA: float = 0.2
const UNALLOCATED_COLOR := Color.DIM_GRAY

var _host: SkillNode


func _ready() -> void:
	_host = owner as SkillNode
	if _host == null:
		return
	_host.radius_changed.connect(queue_redraw)
	_host.owner_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if _host == null:
		return
	var r := _host.radius
	var color := _host.get_owner_color() if _host.is_allocated() else UNALLOCATED_COLOR
	var fill := Color(color.r, color.g, color.b, FILL_ALPHA)
	draw_circle(Vector2.ZERO, r, fill, true)
	draw_circle(Vector2.ZERO, r, color, false, BORDER_WIDTH, true)
