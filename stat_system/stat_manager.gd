@tool
extends Node
class_name StatsManager
## The StatsManager class provides an interface to manage Stats and is typically attached to the entity that owns those stats. 
## This makes it easier to access and manipulate stats during gameplay.

#var _stats: Stats

#signal stats_changed

## Stats holder
var stats: Stats:
	get = _get_stats,
	set = set_stats
	
func set_stats(value: Stats) -> void:
	stats = value

	if stats == null:
		return
	
	for stat_key: GDScript in stats.map.keys():
		var stat := stats.get_stat(stat_key)
		stat.value_changed.connect(_on_stat_value_changed.bind(stat_key, stat))
	
	#_stats = stats.duplicate(true)
	#initialize_replication()  # Sync multiplayer

func _on_stat_value_changed(key: GDScript, stat: Stat) -> void:
	pass
	#print('[%s] CHANGED!\tto: %s' % [stat.name, stat.value])
	#stats_changed.emit()
	#if Game.has_turn(get_parent()):
		#Game.player_stats_changed.emit()


func _get_stats():
	return stats

## Get a specific stat by its key
func get_stat(key: Variant) -> Stat:
	return stats.get_stat(key) if stats != null else null

func get_stats_class_name() -> String:
	return "Stats"

#region Stat Modifiers
## Add a stat modifier to a stat
func add_stat_modifier(stat_modifier: StatModifier) -> void:
	print('[StatsManager]: Adding stat modifier: %s %s' % [stat_modifier.stat_key.get_global_name, stat_modifier])
	if stats == null:
		return

	stats.add_stat_modifier(stat_modifier)

## Remove a stat modifier from a stat
func remove_stat_modifier(stat_modifier: StatModifier) -> void:
	if stats == null:
		return

	stats.remove_stat_modifier(stat_modifier)

## Clear all stat modifiers from all stats
func clear_stat_modifiers() -> void:
	if stats == null:
		return

	stats.clear_stat_modifiers()
#endregion

func _ready() -> void:
	pass
	
#region Multiplayer
####
## MULTIPLAYER (Experimental)
## TODO: Make this a component to attach to a StatsManager
####
#func _ready() -> void:
	#if !is_multiplayer_authority():
		#return
#
	#initialize_replication()
#
#var is_replication_enabled: bool = false
#
### Initialize the replication of all stats to all peers
#func initialize_replication() -> void:
	#if Engine.is_editor_hint():
		#return
#
	#if is_replication_enabled == true or !is_node_ready():
		#return
	#
	#if _stats == null:
		#return
	#
	#for stat_key in _stats.map.keys():
		#_stats.get_stat(stat_key).value_changed.connect(_on_stat_value_changed.bind(stat_key, _stats.get_stat(stat_key)))
	#
	#is_replication_enabled = true
#
#func _on_stat_value_changed(key: GDScript, stat: Stat) -> void:
	#sync_stat.rpc(key.resource_path, stat.value)
#
### Sync the stat value of a specific stat by its key and its current value
#@rpc("call_local", "any_peer")
#func sync_stat(key_path, value) -> void:
	#var key: GDScript = load(key_path)
	#var stat: Stat = get_stat(key)
#
	#if stat:
		#stat.value = value
#endregion

# The magic to add a custom property to manage:
func _get_property_list() -> Array:
	var result: Array = []

	result.append({
		"name": "stats",
		"class_name": &"Resource",
		"type": TYPE_OBJECT,
		"hint": PROPERTY_HINT_RESOURCE_TYPE,
		"hint_string": get_stats_class_name(),
		"usage": Stats.EXPORTED_PROP,
	})

	return result

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	var stats_class: String = get_stats_class_name()
	
	if not stats_class:
		return ['Select stats class to manage']
	
	if stats_class == 'Stats':
		warnings.append('Pick a concrete subclass to manage (not "Stats")')
		
	return warnings
		
