@tool
extends StatsManager
class_name EntityStatsManager


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	super()

func _get_property_list() -> Array:
	var result: Array = []

	result.append({
		"name": "stats",
		"class_name": &"Resource",
		"type": TYPE_OBJECT,
		"hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string": "EntityStats",
		"usage": 4102 })

	return result
