extends Resource
class_name Stat

signal value_changed

#@export var abbreviation: String = ""
#@export var description: String = ""

static func name() -> String:
	return "<full name of stat>"

static func abbreviation()-> String:
	return "<stat abbreviation>"

static func description() -> String:
	return "<stat description>"

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
