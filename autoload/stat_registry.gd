@tool
extends Node

## Global lookup: stat_id → StatDef. Scans stats_system/defs/ on ready.
## Use StatRegistry.get_def(id) wherever you need display info without a board.

const STAT_LIST_DIR: String = "res://stats_system/defs"

var _defs: Dictionary[StringName, StatDef] = {}


func _ready() -> void:
	var dir := DirAccess.open(STAT_LIST_DIR)
	if dir == null:
		push_warning("StatRegistry: could not open %s" % STAT_LIST_DIR)
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres"):
			var res := load(STAT_LIST_DIR + "/" + file)
			if res is StatDef:
				_defs[res.id] = res
		file = dir.get_next()
	dir.list_dir_end()


func get_def(id: StringName) -> StatDef:
	return _defs.get(id, null)


## All registered StatDefs. Order is filesystem-walk order — callers that need
## a stable presentation must impose their own sort (the `display_order` field
## was retired in #120 along with the generic StatsPanel that consumed it).
func get_all_defs() -> Array[StatDef]:
	var out: Array[StatDef] = []
	for def in _defs.values():
		out.append(def)
	return out
