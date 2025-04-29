extends Node
class_name TreeEntity

# Represents an `entity` that lives on a skill tree by owning 1 or more skills on it

@export var core: TreeNode
#@export var stats: Stats = EntityStats.new()
@export_color_no_alpha var color: Color

func _ready() -> void:
	pass

#func _on_child_entered_tree(node: Node) -> void:
	#if node is TreeNode:
		#node.owner = self
#
#func _on_child_exiting_tree(node: Node) -> void:
	#pass # Replace with function body.
