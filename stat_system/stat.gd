extends Resource
class_name Stat


signal value_changed

const STAT_ROW := preload("res://gui/stats_panel/row/stat_row.tscn")

#@export var abbreviation: String = ""
#@export var description: String = ""


## The parent `Stats` board object
var parent: Stats

## Key that defines the uniqueness of a stat
var key: Variant:
	get = get_key

## Base value for stat
var _base_value
var base_value: Variant:
	get = _get_base_value,
	set = _set_base_value
	
func _get_base_value():
	return _base_value
	
func _set_base_value(new_value):
	var _prev = _base_value
	_base_value = new_value
	_on_base_value_changed(_prev, new_value)

## Key getter
func get_key() -> Variant:
	return get_script()

# Value (+ getter only)
var value:
	get = get_value

func get_value():
	return base_value

#region Stat MetaData + caching (stat name, abbreviation, description, ...)
## Static metadata cache var
static var _meta: StatMetaData = null

var FALLBACK: StatMetaData = preload("res://stat_system/fallback_metadata.tres")

## MetaData descriptor (readonly)
var meta: StatMetaData = null:
	get = get_metadata

## Full name of the stat
var name: String:
	get(): return meta.name if meta else 'err'
	
## Abbreviation of the stat
var abbreviation: String:
	get(): return meta.abbreviation
	
## Description of the stat
var description: String:
	get(): return meta.description

## Lookup metadata unless static var cache has been set
func get_metadata() -> StatMetaData:
	if not meta:
		if not StatMetaDataRepository.is_node_ready():
			return FALLBACK
		_meta = StatMetaDataRepository.get_by_key(get_script())
	return _meta
	
#endregion

## Display value, essentially a string representation of the value of a stat
func display_value() -> String:
	return "%s" % value


func _on_base_value_changed(old_value, new_value):
	pass

func _get_stat_row_resource() -> Resource:
	return STAT_ROW

func _generate_row(manager: StatsManager) -> StatRowBase:
	var row: StatRowBase = _get_stat_row_resource().instantiate()
	#print('Setting manager to %s' % manager)
	row.stat_manager = manager
	#print('Setting stat key to %s' % get_key())
	row.stat_key = get_key()
	#print('Setting stat text display to %s' % name)
	row.text_display = name
	#row.value_display = "%s" % [display_value()]
	#print('Final settings: %s %s %s %s' % [row.stat_manager, row.stat_key, row.text_display, row.value_display])
	return row

func notify_value_changed() -> void:
	notify_property_list_changed()
	print_debug('[%s]: EMITTING value_changed' % [name])
	value_changed.emit()

###
# STAT MODIFIERS
###
#func add_stat_modifier(stat_modifier) -> void:
	#pass
#
#func remove_stat_modifier(stat_modifier) -> void:
	#pass
#
#func clear_stat_modifiers() -> void:
	#pass
