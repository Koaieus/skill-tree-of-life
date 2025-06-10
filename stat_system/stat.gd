extends Resource
class_name Stat


signal value_changed

const STAT_ROW := preload("res://gui/stats_panel/row/stat_row.tscn")

#@export var abbreviation: String = ""
#@export var description: String = ""

static func name() -> String:
	return "<nameless stat>"

static func abbreviation()-> String:
	return "<stat abbreviation>"

static func description() -> String:
	return "<stat description>"

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

func display_value() -> String:
	return "%s" % value


func _on_base_value_changed(old_value, new_value):
	pass

func _get_stat_row_resource() -> Resource:
	return STAT_ROW

func _generate_row(manager: StatsManager) -> StatRow:
	var row: StatRow = _get_stat_row_resource().instantiate()
	#print('Setting manager to %s' % manager)
	row.stat_manager = manager
	#print('Setting stat key to %s' % get_key())
	row.stat_key = get_key()
	#print('Setting stat text display to %s' % name())
	row.text_display = name()
	#row.value_display = "%s" % [display_value()]
	#print('Final settings: %s %s %s %s' % [row.stat_manager, row.stat_key, row.text_display, row.value_display])
	return row

func notify_value_changed() -> void:
	print_debug('[%s]: EMITTING value_changed' % [name()])
	value_changed.emit()
	notify_property_list_changed()

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
