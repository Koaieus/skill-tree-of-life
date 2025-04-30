@tool
extends GraphEdit

const tree_node_packed = preload("res://tree_node.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	connect_node(from_node, from_port, to_node, to_port)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)

func add_new_skill_node() -> void:
	var new_node := tree_node_packed.instantiate()
	add_child(new_node)

func _on_insert_add_new_skill_node() -> void:
	pass # Replace with function body.


func _on_popup_request(at_position: Vector2) -> void:
	print('Poppin up at', at_position)
	var rect = Rect2i(at_position, Vector2i(100,100))
	%ContextMenu.popup(rect)

#func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	#return PackedVector2Array([from_position, to_position])
