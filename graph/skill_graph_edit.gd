extends GraphEdit
class_name SkillGraphEdit

signal node_added(new_node: TreeNode)
signal node_removing(leaving_node: TreeNode)
signal nodes_connected(from_node: TreeNode, to_node: TreeNode)
signal nodes_disconnected(from_node: TreeNode, to_node: TreeNode)


## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#pass # Replace with function body.
