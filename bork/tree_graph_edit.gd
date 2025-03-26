@tool
extends GraphEdit

var tree_node_packed = preload("res://bork/tree_node.tscn")

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
