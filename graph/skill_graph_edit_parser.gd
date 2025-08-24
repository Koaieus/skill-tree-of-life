extends Node
class_name SkillGraphEditParser

static func populate_world_from_edit(graph_edit: SkillGraphEdit, graph_world: SkillGraphWorld, clear_first: bool = false) -> void:
	# 1) Clear world
	if clear_first:
		graph_world.clear_world()

	# 2) Nodes
	for tn in graph_edit.get_children():
		if tn is TreeNode:
			var pos = tn.position_offset
			var node: SkillNode2D = graph_world.add_skill_node_from_skill_data(tn.name, pos, tn.skill_data)
			# Some rng BS to showcase physics
			node.mass = randf_range(0.3,  3.0)

	# 3) Edges
	for c in graph_edit.get_connection_list():
		graph_world.connect_nodes(
			graph_world.node_map.get(c.from_node), 
			graph_world.node_map.get(c.to_node)
		)
