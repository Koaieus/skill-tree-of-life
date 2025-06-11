extends Node
class_name Navigator

var astar: AStar2D = AStar2D.new()



func _on_tree_graph_edit_nodes_connected(from_node: GraphNode, to_node: GraphNode) -> void:
	if from_node is TreeNode and to_node is TreeNode:
		print('[Nav]: Connecting %s to %s' % [from_node, to_node])
		astar.connect_points(from_node.get_instance_id(), to_node.get_instance_id())


func _on_tree_graph_edit_nodes_disconnected(from_node: GraphNode, to_node: GraphNode) -> void:
	if from_node is TreeNode and to_node is TreeNode:
		print('[Nav]: Disonnecting %s to %s' % [from_node, to_node])
		astar.disconnect_points(from_node.get_instance_id(), to_node.get_instance_id())


func _on_tree_graph_edit_node_added(new_node: TreeNode) -> void:
	print('[Nav]: Adding %s at %s' % [new_node, new_node.position_offset])
	astar.add_point(new_node.get_instance_id(), new_node.position_offset)


func _on_tree_graph_edit_node_removing(leaving_node: TreeNode) -> void:
	print('[Nav]: Removing %s' % [leaving_node])
	astar.remove_point(leaving_node.get_instance_id())
