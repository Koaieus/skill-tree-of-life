@tool 
class_name Edge extends Line2D

@export var node1: Node
@export var node2: Node

func _ready():
	#add_point(Vector2())
	#add_point(node2.global_position - node1.global_position)
	update_position()

func update_position() -> void:
	print('updating position')
	global_position = node1.global_position
	set_point_position(1, node2.global_position - node1.global_position)

func get_other_node(from: Node2D) -> Node2D:
	return node1 if from == node2 else node2

func _on_tree_entered():
	print('on tree entered')
	if node1 and node2:
		update_position()
