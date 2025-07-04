#@tool
extends GraphEdit
class_name TreeGraph

const tree_node_packed = preload("res://tree_node.tscn")

signal node_added(new_node: TreeNode)
signal node_removing(leaving_node: TreeNode)
signal nodes_connected(from_node: TreeNode, to_node: TreeNode)
signal nodes_disconnected(from_node: TreeNode, to_node: TreeNode)

signal connection_path_calculated(path : PackedVector2Array)

@onready var navigator: Navigator = $Navigator 
@onready var turn_manager: TurnManager = $TurnManager

var beam_packed: PackedScene = preload("res://vfx/edge_beam.tscn")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#Game.tree_graph = self
	#Game.navigator = navigator
	#Game.turn_manager = turn_manager

	# Signal for each pre-defined connections:
	for conn in connections:
		notify_nodes_connected(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
	
	for child in get_children():
		if child is TreeNode:
			child.allocated.connect(_on_node_allocated)
	#Game.game_ready.emit.call_deferred()

## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass



func add_new_skill_node() -> void:
	var new_node := tree_node_packed.instantiate()
	add_child(new_node)

## Forces internal graph to be rebuilt from scratch
func rebuild_graph() -> void:
	print('Rebuilding graph...')
	assert(is_node_ready(), 'Cannot rebuild graph if node is not ready yet.')
	# Clear AStar
	navigator.astar.clear()
	navigator.assign_vertex_ids_to_all_nodes(self)



#region Signal Emission methods
func notify_nodes_connected(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	nodes_connected.emit(get_node(NodePath(from_node)), get_node(NodePath(to_node)))


func notify_nodes_disconnected(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	nodes_disconnected.emit(get_node(NodePath(from_node)), get_node(NodePath(to_node)))
#endregion


#region Event Handlers
func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if not connect_node(from_node, from_port, to_node, to_port):
		notify_nodes_connected(from_node, from_port, to_node, to_port)
	

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	notify_nodes_disconnected(from_node, from_port, to_node, to_port)


#region VFX
func create_beam_along_edge(from_node: TreeNode, to_node: TreeNode) -> EdgeBeam:
	var beam: EdgeBeam = beam_packed.instantiate()
	var points = get_connection_line(from_node.position, to_node.position)
	add_child(beam)
	beam.start(points)
	return beam
#endregion


func _on_insert_add_new_skill_node() -> void:
	pass # Replace with function body.


func _on_nodes_connected(from_node: TreeNode, to_node: TreeNode) -> void:
	print('[TreeGraph] Connected nodes %s and %s' % [from_node, to_node])
	
	from_node.add_neighbor(to_node)
	to_node.add_neighbor(from_node)

func _on_nodes_disconnected(from_node: TreeNode, to_node: TreeNode) -> void:
	print('[TreeGraph] Disconnected nodes %s and %s' % [from_node, to_node])


func _on_node_allocated(node: TreeNode, entity: TreeEntity):
	print('[TreeGraph] NODE ALLOCATED: %s' % node)
	for neighbor in node.neighbors:
		if neighbor.owned_by == entity:
			print('[VFX] Creating beam from %s to %s!' % [neighbor, node])
			create_beam_along_edge(node, neighbor)

func _on_popup_request(at_position: Vector2) -> void:
	print('Poppin up at', at_position)
	var rect = Rect2i(at_position, Vector2i(100,100))
	%ContextMenu.popup(rect)

#func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	#PackedVector2Array([from_position, to_position])

func _on_child_entered_tree(node: Node) -> void:
	if node is TreeNode:
		node_added.emit(node as TreeNode)

func _on_child_exiting_tree(node: Node) -> void:
	if node is TreeNode:
		node_removing.emit(node as TreeNode)
#endregion
