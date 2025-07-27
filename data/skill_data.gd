extends Resource
class_name SkillData

@export var name: String            # unique (for save / network)
@export var desc: String

@export var modifiers: Array[StatModifier] = []
@export var icon: Texture2D

@export var vision_range: int = 100

#@export var prefab_entity: PackedScene = null
