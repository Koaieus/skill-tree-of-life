@tool
extends Resource
class_name StatModifier

signal apply_count_changed()

## Key for identifying the stat it acts on
@export var stat_key: GDScript

### Order in which the modifier is applied   (application: in ASCENDING order)
var application_order: int = 1000;

## How many times this stat is applied
var apply_count: int = 1:
	set = set_apply_count

func set_apply_count(value: int) -> void:
	apply_count = value
	apply_count_changed.emit()


func compatible_with(stat: Stat) -> bool:
	return stat_key == stat.key


func as_string() -> String:
	return "<stat modifier>"
