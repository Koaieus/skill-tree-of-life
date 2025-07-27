extends Node
class_name Navigator

var astar := AStarSkillTree.new()

@export var vtx_to_node_map: Dictionary[int, SkillNode2D]

func _ready() -> void:
	astar.clear()

## Returns the vertex id (int) for this node, assigns new value if unset (-1)
func node_to_vertex_id(tree_node: SkillNode2D) -> int:
	# Initialize vertex ID if not set — this Navigator's AStar is leading
	if tree_node.vertex_id == -1:
		assign_vertex_id_to_node(tree_node)
	return tree_node.get_vertex_id()
	
func get_node_from_vertex_id(vertex_id: int) -> SkillNode2D:
	return vtx_to_node_map.get(vertex_id) as SkillNode2D
	
func assign_vertex_id_to_node(node: SkillNode2D, force_reset: bool = false) -> int:
	if not force_reset:
		assert(
			node.vertex_id == -1,  
			'Trying to change vertex ID of SkillNode2D %s that already has vertex_id=%s' % [node, node.vertex_id]
		)
	# Get next available vertex ID from astar
	var new_id = astar.get_available_point_id()
	node.vertex_id = new_id
	vtx_to_node_map[new_id] = node
	return new_id

func assign_vertex_ids_to_all_nodes(sgw: SkillGraphWorld) -> void:
	for child in sgw.get_children():
		if child is SkillNode2D:
			assign_vertex_id_to_node(child, true)

#region AStar Point manipulation API
func _add_point(node: SkillNode2D) -> void:
	print('[Nav]: Adding %s at %s' % [node, node.global_position])
	astar.add_point(node_to_vertex_id(node), node.global_position)

func _remove_point(node: SkillNode2D) -> void:
	print('[Nav]: Removing %s' % [node])
	astar.remove_point(node_to_vertex_id(node))
	
func _connect_points(node1: SkillNode2D, node2: SkillNode2D):
	print('[Nav]: Connecting %s to %s' % [node1, node2])
	astar.connect_points(node_to_vertex_id(node1), node_to_vertex_id(node2))

func _disconnect_points(node1: SkillNode2D, node2: SkillNode2D):
	print('[Nav]: Disonnecting %s to %s' % [node1, node2])
	astar.disconnect_points(node_to_vertex_id(node1), node_to_vertex_id(node2))
#endregion
	
	
#region Event handlers
func _on_skill_graph_node_added(new_node: SkillNode2D) -> void:
	_add_point(new_node)

func _on_skill_graph_node_removing(leaving_node: SkillNode2D) -> void:
	_remove_point(leaving_node)

func _on_skill_graph_nodes_connected(from_node: SkillNode2D, to_node: SkillNode2D) -> void:
	_connect_points(from_node, to_node)

func _on_skill_graph_nodes_disconnected(from_node: SkillNode2D, to_node: SkillNode2D) -> void:
	_disconnect_points(from_node, to_node)
#endregion
