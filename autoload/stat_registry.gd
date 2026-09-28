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
## Parent graph over [member StatDef.parent_ids], built by [method _rebuild_graph]:
## id -> transitive ancestors nearest-first, and parent id -> direct children.
var _ancestors: Dictionary = {}
var _children: Dictionary = {}


func _ready() -> void:
	var roster := load(ROSTER_PATH) as StatDefRoster
	if roster == null:
		push_warning("StatRegistry: could not load %s" % ROSTER_PATH)
		return
	for def in roster.defs:
		if def != null:
			_defs[def.id] = def
	_rebuild_graph()


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



## Transitive ancestors of [param id], nearest-first, deduped (breadth-first
## over the accepted [member StatDef.parent_ids] edges). Empty for a stat with
## no parents or an unknown id.
func ancestors_of(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_ancestors.get(id, []))
	return out


## Direct children of [param id] — the stats whose accepted `parent_ids` name it.
func children_of(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_children.get(id, []))
	return out


func is_parent(id: StringName) -> bool:
	return _children.has(id)


## True iff any registered def has an accepted parent edge — lets a board skip
## its link pass entirely on a roster with no parents.
func has_parents() -> bool:
	return not _children.is_empty()


## [b]Test seam only[/b] — nothing outside `test/` calls this. Registers a
## throwaway def and recomputes the ancestor graph, so a test arranges
## `parent_ids` without touching the roster. Pair with [method unregister_def].
func register_def(def: StatDef) -> void:
	_defs[def.id] = def
	_rebuild_graph()


## [b]Test seam only[/b] — undoes [method register_def].
func unregister_def(id: StringName) -> void:
	_defs.erase(id)
	_rebuild_graph()


## Accepts each def's `parent_ids` edge by edge in sorted-id order: an unknown
## parent id, or an edge that would close a cycle, is `push_error`ed and
## dropped (the def resource itself is never mutated). Then flattens every
## id's ancestors nearest-first.
func _rebuild_graph() -> void:
	var parents: Dictionary = {}  # id -> Array[StringName], accepted direct edges
	_children.clear()
	_ancestors.clear()
	var ids: Array = _defs.keys()
	ids.sort()
	for id in ids:
		for pid in _defs[id].parent_ids:
			if not _defs.has(pid):
				push_error("StatRegistry: '%s' names unknown parent id '%s' — edge dropped" % [id, pid])
				continue
			if pid == id or _reaches(pid, id, parents):
				push_error("StatRegistry: parent edge '%s' -> '%s' closes a cycle — edge dropped" % [id, pid])
				continue
			var ps: Array = parents.get(id, [])
			if ps.has(pid):
				continue
			ps.append(pid)
			parents[id] = ps
			var cs: Array = _children.get(pid, [])
			cs.append(id)
			_children[pid] = cs
	for id in parents:
		var out: Array = []
		var frontier: Array = parents[id].duplicate()
		while not frontier.is_empty():
			var next: Array = []
			for a in frontier:
				if out.has(a):
					continue
				out.append(a)
				next.append_array(parents.get(a, []))
			frontier = next
		_ancestors[id] = out


## Whether [param target] is an ancestor of (or is) [param from] over [param parents].
func _reaches(from: StringName, target: StringName, parents: Dictionary) -> bool:
	var stack: Array = [from]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var cur: StringName = stack.pop_back()
		if cur == target:
			return true
		if seen.has(cur):
			continue
		seen[cur] = true
		stack.append_array(parents.get(cur, []))
	return false
