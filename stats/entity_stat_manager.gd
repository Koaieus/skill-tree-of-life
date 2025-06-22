@tool
extends StatsManager
class_name EntityStatsManager

signal initiative_ready(state: bool)

func get_stats_class_name():
	return "EntityStats"

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	super()
	
	_stats.initiative.initiative_ready.connect(func(rdy): initiative_ready.emit(rdy))

var _stats: EntityStats:
	get = _get_stats

func _get_stats() -> EntityStats:
	return stats

func progress_initiative():
	#print('[INITIATIVE]: %s +%s' % [stats.initiative.value, stats.initiative.progress])
	stats.initiative.progress += stats.initiative.value
