extends Node
class_name TreeEntity

# Represents an `entity` that lives on a skill tree by owning 1 or more skills on it

@export var core: TreeNode
#@export var stats: Stats = EntityStats.new()
@export_color_no_alpha var color: Color

@onready var _stats: EntityStatsManager = $EntityStatsManager

func _ready() -> void:
	pass

func allocate_skill_node(skill_node: TreeNode) -> bool:
	if 
