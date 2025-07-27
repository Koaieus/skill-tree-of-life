extends Node
class_name SkillGraphEditParser

static func populate_world_from_edit(graph_edit: SkillGraphEdit, graph_world: SkillGraphWorld) -> void:
	# 1) Clear world
	graph_world.clear_world()

	# 2) Nodes
	for tn in graph_edit.get_children():
		if tn is TreeNode:
			var pos = tn.position_offset
			var node: SkillNode2D = graph_world.add_skill_node_from_skill_data(tn.name, pos, tn.skill_data)
			# Randomly freeze
			if randf() < 0.15:
				node.freeze = true
				node.modulate = Color.SADDLE_BROWN

	# 3) Edges
	for c in graph_edit.get_connection_list():
		graph_world.connect_nodes(
			graph_world.node_map.get(c.from_node), 
			graph_world.node_map.get(c.to_node)
		)
