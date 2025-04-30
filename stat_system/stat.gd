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

## Key that defines the uniqueness of a stat
var key: Variant:
	get = get_key

## Base value for stat
var base_value

## Key getter
func get_key() -> Variant:
	return get_script()

# Value (+ getter only)
var value:
	get = get_value

func get_value():
	return base_value


###
# STAT MODIFIERS
###
func add_stat_modifier(stat_modifier) -> void:
	pass

func remove_stat_modifier(stat_modifier) -> void:
	pass

func clear_stat_modifiers() -> void:
	pass
