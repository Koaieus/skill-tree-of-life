@tool
class_name BladeEdge
extends Area2D

signal endpoints_changed

@export var from: BladeNode:
	set(value):
		from = value
		endpoints_changed.emit()
		queue_redraw()

@export var to: BladeNode:
	set(value):
		to = value
		endpoints_changed.emit()
		queue_redraw()

@export var width: float = 2.0
@export var color: Color = Color(1.0, 0.184, 0.18, 1.0)

@onready var _col: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_update_collision()

func _process(_delta: float) -> void:
	queue_redraw()
	_update_collision()

func _draw() -> void:
	if from == null or to == null:
		return
	var a := to_local(from.edge_point(to.global_position))
	var b := to_local(to.edge_point(from.global_position))
	if (b - a).length_squared() < 0.01:
		return
	draw_line(a, b, color, width, true)

func _update_collision() -> void:
	if _col == null or from == null or to == null:
		return
	var shape := _col.shape as SegmentShape2D
	if shape == null:
		return
	var a := to_local(from.edge_point(to.global_position))
	var b := to_local(to.edge_point(from.global_position))
	if (b - a).length_squared() < 0.01:
		_col.disabled = true
		return
	_col.disabled = false
	shape.a = a
	shape.b = b
