@tool
extends Node2D

var _host: SkillNode


func _ready() -> void:
	_host = owner as SkillNode
	if _host == null:
		return
	_host.radius_changed.connect(queue_redraw)
	_host.owner_changed.connect(queue_redraw)


func _draw() -> void:
	if _host == null:
		return
	var r := _host.radius - 6
	draw_circle(Vector2.ZERO, r, _host.get_owner_color(), true)
