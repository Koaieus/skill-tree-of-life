@tool
extends Node

## Global lookup: stat_id → StatDef, from the authored [StatDefRoster].
## Use StatRegistry.get_def(id) wherever you need display info without a board.
##
## [b]It reads a roster and does NOT scan [constant STAT_LIST_DIR].[/b] It used
## to, and that made every stat lookup fail in an exported build: the exporter
## rewrites each `.tres` into a `.res` + `.tres.remap` pair inside the PCK, so
## `ends_with(".tres")` matches nothing and the registry came up empty — 20
## `unknown stat id` / `def missing` warnings on the first frame of a build,
## none of them reproducible from source. Same bug #640 fixed for
## [CoreClassRoster], and the same fix: per #597 D13, runtime reads an authored
## array of `ExtResource` edges, which no remap and no export filter can rename
## out from under it.
##
## The directory is still named here because the drift test
## (`test/unit/test_stat_def_roster.gd`) compares it against the roster — that
## test, not a fallback scan, is what stops an unlisted def going missing.

const STAT_LIST_DIR: String = "res://stats_system/defs"
const ROSTER_PATH: String = "res://stats_system/stat_def_roster.tres"

var _defs: Dictionary[StringName, StatDef] = {}


func _ready() -> void:
	var roster := load(ROSTER_PATH) as StatDefRoster
	if roster == null:
		push_warning("StatRegistry: could not load %s" % ROSTER_PATH)
		return
	for def in roster.defs:
		if def != null:
			_defs[def.id] = def


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
