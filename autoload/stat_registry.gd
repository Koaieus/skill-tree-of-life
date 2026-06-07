extends Node

## Global lookup: stat_id → StatDef. Scans stats_system/list/ on ready.
## Use StatRegistry.get_def(id) wherever you need display info without a board.

var _defs: Dictionary = {}


func _ready() -> void:
	var dir := DirAccess.open("res://stats_system/list")
	if dir == null:
		push_warning("StatRegistry: could not open res://stats_system/list")
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres"):
			var res := load("res://stats_system/list/" + file)
			if res is StatDef:
				_defs[res.id] = res
		file = dir.get_next()
	dir.list_dir_end()


func get_def(id: StringName) -> StatDef:
	return _defs.get(id, null)
