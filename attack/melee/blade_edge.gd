@tool
class_name BladeEdge
extends Area2D

## Damaging, visible edge between two BladeNodes of a SkillBlade
## > "Don't cut yourself on that edge... Cut your enemies with it instead"

signal endpoints_changed

@export var from: BladeNode:
	set(value):
		if from == value:
			return
		_disconnect_endpoint(from)
		from = value
		_connect_endpoint(from)
		endpoints_changed.emit()
		_update_endpoints()

@export var to: BladeNode:
	set(value):
		if to == value:
			return
		_disconnect_endpoint(to)
		to = value
		_connect_endpoint(to)
		endpoints_changed.emit()
		_update_endpoints()

@export var width: float = 2.0
@export var color: Color = Color(1.0, 0.184, 0.18, 1.0)


@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D  # has a SegmentShape (line between `a` and `b` points)


func _ready() -> void:
	collision_shape_2d.shape.a = Vector2.ZERO
	_update_endpoints()
	

func _draw() -> void:
	if from == null or to == null:
		return
	var a := from.global_position - global_position
	var b := to.global_position - global_position                                                                                                            
	var dir := (b - a).normalized()
	var a_trim := a + dir * from.radius                                                                                                                      
	var b_trim := b - dir * to.radius                           
	if (b_trim - a_trim).dot(dir) <= 0.0:                                                                                                                    
		return  # nodes overlap — nothing to draw
	draw_line(a_trim, b_trim, color, width, true)  


func _connect_endpoint(node: BladeNode) -> void:
	if node == null:
		return
	if not node.item_rect_changed.is_connected(_on_endpoint_move):
		node.item_rect_changed.connect(_on_endpoint_move)



func _disconnect_endpoint(node: BladeNode) -> void:
	if node == null:
		return
	if node.item_rect_changed.is_connected(_on_endpoint_move):
		node.item_rect_changed.disconnect(_on_endpoint_move)

func _update_endpoints() -> void:
	if collision_shape_2d:
		var shape: SegmentShape2D = collision_shape_2d.shape
		if from and to:
			collision_shape_2d.disabled = false
			shape.a = from.position
			shape.b = to.position
			print('Updated pos to', shape.a, shape.b)
		else:
			collision_shape_2d.disabled = true
	queue_redraw()


func _on_endpoint_move() -> void:
	_update_endpoints()
