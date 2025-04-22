@tool
extends EditorScript


# Called when the script is executed (using File -> Run in Script Editor).
func _run() -> void:
	connect_nodes()

func connect_nodes():
	#var scene = get_scene()
	var selection := get_editor_interface().get_selection().get_selected_nodes()
	if selection.is_empty():
		print('Empty selection')
		return
	
	if selection.size() != 2:
		print('Must select exactly 2 `GraphNode`s')
		return
		
	# Verify node configuration
	for node in selection:
		
		if node.get_class() != 'GraphNode':
			print('Must connect two nodes of type `GraphNode`')
			print('Found: ', node.get_class())
			return
		var parent = node.get_parent()
		if not parent:
			print('No parent')
			return
		if parent.get_class() != 'GraphEdit':
			print('Must connect two nodes that are children of a `GraphEdit`')
			return
		print('Connecting: ', node.name)
		
	var node1: GraphNode = selection[0]
	var node2: TreeNode = selection[1]
	
	# Verify they have the same parent
	if node1.get_parent() != node2.get_parent():
		print('Nodes must have the same parent')
		return
	
	var parent: GraphEdit = node1.get_parent()
	
	print('connecting!')
	
	parent.connect_node(node1.name, 0, node2.name, 0)
