@tool
extends Node2D

const BORDER_WIDTH: float = 2.0
const FILL_ALPHA: float = 0.7

var _host: BladeNode


func _ready() -> void:
	_init_host()


func _notification(what: int) -> void:
	# This triggers automatically in the editor when you save changes to this script
	if what == NOTIFICATION_EDITOR_POST_SAVE:
		_init_host()


func _init_host() -> void:
	_host = owner as BladeNode
	if _host:
		queue_redraw()


func _draw() -> void:
	if _host == null:
		return
	var r := _host.radius
	var color := Color.FIREBRICK if not _host.is_pivot else Color.CHOCOLATE
	var fill := Color(color.r, color.g, color.b, FILL_ALPHA)
	draw_circle(Vector2.ZERO, r, fill, true)
	draw_circle(Vector2.ZERO, r, color, false, BORDER_WIDTH, true)
