@tool
extends Node2D

const BORDER_WIDTH: float = 2.0
const FILL_ALPHA: float = 0.2

var _host: SkillNode


func _ready() -> void:
	_host = owner as SkillNode
	if _host == null:
		return
	_host.radius_changed.connect(queue_redraw)
	_host.allocation_state_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if _host == null:
		return
	var r := _host.radius
	var color := _color_for_state(_host.allocation_state)
	var fill := Color(color.r, color.g, color.b, FILL_ALPHA)
	draw_circle(Vector2.ZERO, r, fill, true)
	draw_circle(Vector2.ZERO, r, color, false, BORDER_WIDTH, true)


func _color_for_state(state: int) -> Color:
	match state:
		SkillNode.AllocationState.UNALLOCATED:
			return Color.DIM_GRAY
		SkillNode.AllocationState.ALLOCATED:
			return Color.WHITE
		SkillNode.AllocationState.LOCKED:
			return Color.INDIAN_RED
		_:
			return Color.MAGENTA
