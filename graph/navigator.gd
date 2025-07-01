extends Node
class_name Navigator

var astar := AStarSkillTree.new()

@export var vtx_to_node_map: Dictionary[int, TreeNode]

func _ready() -> void:
	astar.clear()

## Returns the vertex id (int) for this node, assigns new value if unset (-1)
func node_to_vertex_id(tree_node: TreeNode) -> int:
	# Initialize vertex ID if not set — this Navigator's AStar is leading
	if tree_node._vertex_id == -1:
		assign_vertex_id_to_node(tree_node)
	return tree_node.get_vertex_id()
	
func get_node_from_vertex_id(vertex_id: int) -> TreeNode:
	return vtx_to_node_map.get(vertex_id) as TreeNode
	
func assign_vertex_id_to_node(node: TreeNode, force_reset: bool = false) -> int:
	if not force_reset:
		assert(node._vertex_id == -1, 'Trying to change vertex ID of %s having vertex_id=%s' % [node, node._vertex_id])
	# Get next available vertex ID from astar
	var new_id = astar.get_available_point_id()
	node._vertex_id = new_id
	vtx_to_node_map[new_id] = node
	return new_id

func assign_vertex_ids_to_all_nodes(tree_graph: TreeGraph) -> void:
	for child in tree_graph.get_children():
		if child is TreeNode:
			assign_vertex_id_to_node(child, true)

#region AStar Point manipulation API
func _add_point(node: TreeNode) -> void:
	astar.add_point(node_to_vertex_id(node), node.position_offset)

func _remove_point(node: TreeNode) -> void:
	astar.remove_point(node_to_vertex_id(node))
	
func _connect_points(node1: TreeNode, node2: TreeNode):
	astar.connect_points(node_to_vertex_id(node1), node_to_vertex_id(node2))

func _disconnect_points(node1: TreeNode, node2: TreeNode):
	astar.disconnect_points(node_to_vertex_id(node1), node_to_vertex_id(node2))
#endregion
	
	
#region Event handlers
func _on_tree_graph_node_added(new_node: TreeNode) -> void:
	print('[Nav]: Adding %s at %s' % [new_node, new_node.position_offset])
	_add_point(new_node)

func _on_tree_graph_node_removing(leaving_node: TreeNode) -> void:
	print('[Nav]: Removing %s' % [leaving_node])
	_remove_point(leaving_node)

func _on_tree_graph_nodes_connected(from_node: TreeNode, to_node: TreeNode) -> void:
	#if from_node is TreeNode and to_node is TreeNode:
	print('[Nav]: Connecting %s to %s' % [from_node, to_node])
	_connect_points(from_node, to_node)

func _on_tree_graph_nodes_disconnected(from_node: TreeNode, to_node: TreeNode) -> void:
	#if from_node is TreeNode and to_node is TreeNode:
	print('[Nav]: Disonnecting %s to %s' % [from_node, to_node])
	_disconnect_points(from_node, to_node)
#endregion
