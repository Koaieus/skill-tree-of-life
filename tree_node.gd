@tool 
class_name TreeNode
extends GraphNode

## Skill Data resource
@export var skill_data: SkillData = SkillData.new()

### Tooltip resource [preloaded]
#@onready var tool_tip: PackedScene = preload("res://ui/tooltip.tscn")


## Point ID for use in A* implementation (internal value, only Navigator class should set this!)
var vertex_id: int = -1:
	get = get_vertex_id,
	set = set_vertex_id

func get_vertex_id(): return vertex_id
func set_vertex_id(v):
	vertex_id = max(v, -1)
	notify_property_list_changed()

## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#pass
#
#
## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass
