@tool
extends GraphEdit
class_name TreeGraphEdit

const tree_node_packed = preload("res://tree_node.tscn")

signal node_added(new_node: TreeNode)
signal node_removing(leaving_node: TreeNode)
signal nodes_connected(from_node: TreeNode, to_node: TreeNode)
signal nodes_disconnected(from_node: TreeNode, to_node: TreeNode)

@onready var nav: Navigator = $Navigator


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Signal for each pre-defined connections:
	for conn in connections:
		notify_nodes_connected(conn.from_node, conn.from_port, conn.to_node, conn.to_port)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if not connect_node(from_node, from_port, to_node, to_port):
		notify_nodes_connected(from_node, from_port, to_node, to_port)
	

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	notify_nodes_disconnected(from_node, from_port, to_node, to_port)



func add_new_skill_node() -> void:
	var new_node := tree_node_packed.instantiate()
	add_child(new_node)


func notify_nodes_connected(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	nodes_connected.emit(get_node(NodePath(from_node)), get_node(NodePath(to_node)))


func notify_nodes_disconnected(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	nodes_disconnected.emit(get_node(NodePath(from_node)), get_node(NodePath(to_node)))


func _on_insert_add_new_skill_node() -> void:
	pass # Replace with function body.


func _on_nodes_connected(from_node: GraphNode, to_node: GraphNode) -> void:
	print('[TreeGraphEdit] Connected nodes %s and %s' % [from_node, to_node])

func _on_nodes_disconnected(from_node: GraphNode, to_node: GraphNode) -> void:
	print('[TreeGraphEdit] Disconnected nodes %s and %s' % [from_node, to_node])


func _on_popup_request(at_position: Vector2) -> void:
	print('Poppin up at', at_position)
	var rect = Rect2i(at_position, Vector2i(100,100))
	%ContextMenu.popup(rect)

#func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	#return PackedVector2Array([from_position, to_position])


func _on_child_entered_tree(node: Node) -> void:
	if node is TreeNode:
		node_added.emit(node)

func _on_child_exiting_tree(node: Node) -> void:
	if node is TreeNode:
		node_removing.emit(node)
