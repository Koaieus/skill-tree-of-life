extends Node
class_name TreeEntity

# Represents an `entity` that lives on a skill tree by owning 1 or more skills on it

@export var core: TreeNode
#@export var stats: Stats = EntityStats.new()
@export_color_no_alpha var color: Color

@onready var _stats: EntityStatsManager = $EntityStatsManager

func _ready() -> void:
	print('TreeEntity READY')
	if core:
		core.allocate_to(self)
		print('Allocated core')
	else:
		print('No Core')

func can_allocate_node(tree_node: TreeNode) -> bool:
	if tree_node.has_owner():
		return false
	return true
	
func can_deallocate_node(tree_node: TreeNode) -> bool:
	if tree_node.owned_by != self:
		return false
	return true
	
func _pay_allocation_cost(tree_node: TreeNode):
	return
	
func allocate_skill_node(tree_node: TreeNode):
	prints('Allocating', tree_node, 'to', self)
	if not can_allocate_node(tree_node):
		print('Cannot allocate!')
		return false
	_pay_allocation_cost(tree_node)
	tree_node.owned_by = self
	
func deallocate_skill_node(tree_node: TreeNode):
	prints('Deallocating', tree_node, 'from', self)
	tree_node.owned_by = null
	return false
