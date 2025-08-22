extends Resource
class_name SkillData

@export var name: String            # unique (for save / network)
@export var desc: String

@export var modifiers: Array[StatModifier] = []
@export var icon: Texture2D

@export_range(0., 10., 0.1) var pressure: float= 1.0
@export var vision_range: int = 100

@export var is_starter_node: bool = false

#@export var prefab_entity: PackedScene = null
