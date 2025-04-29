@tool
extends StatsManager
class_name EntityStatsManager

func get_stats_class_name():
	return "EntityStats"

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	super()
