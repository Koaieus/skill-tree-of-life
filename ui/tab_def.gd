@tool
class_name TabDef
extends Resource

## Typed descriptor for one [StatsPanel] tab — replaces the old loose
## Array[Dictionary]. [member glyph] accepts a String (unicode stopgap) or a
## Texture2D (real icon); StatsPanel dispatches on the runtime type, so swapping
## an emoji for an icon is a data change, no code edit.

@export var id: StringName = &""
@export var name: String = ""
## String | Texture2D. Untyped so a tab can carry either; StatsPanel branches.
@export var glyph: Variant = ""


func _init(p_id: StringName = &"", p_name: String = "", p_glyph: Variant = "") -> void:
	id = p_id
	name = p_name
	glyph = p_glyph
