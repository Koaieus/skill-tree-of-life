extends GutTest

## Authoring lint: every authored SET [StatModifier] holds a `priority`
## unique to its `stat_id`. Two distinct entries on one stat at equal priority
## fail even when their values match — a deliberate copy is one shared
## resource, and the same resource referenced twice counts once. SETs built
## in code are backstopped at bind time by `ModifierBins.add`'s push_error.
##
## Walks every `.tres` / `.tscn` under res:// except the import cache, tests
## and third-party addons. A file is only loaded if its text carries an
## `operation = ` line: a SET is never the default op, so it is always
## serialized there.

const _SKIP_DIRS := [
	"res://.godot", "res://test", "res://addons/gut",
	"res://addons/godot-git-plugin", "res://addons/godot-neovim",
]


func test_authored_set_priorities_are_unique_per_stat() -> void:
	var files: Array[String] = []
	_collect_files("res://", files)
	assert_gt(files.size(), 0, "precondition: the walk found resource files")

	# instance_id -> [StatModifier, source path]; dedupes a shared resource.
	var sets: Dictionary = {}
	for path in files:
		if not FileAccess.get_file_as_string(path).contains("operation = "):
			continue
		var res := ResourceLoader.load(path)
		if res is PackedScene:
			var state := (res as PackedScene).get_state()
			for n in state.get_node_count():
				for p in state.get_node_property_count(n):
					_walk(state.get_node_property_value(n, p), path, sets, {})
		else:
			_walk(res, path, sets, {})
	assert_gt(sets.size(), 0, "precondition: pacifist_core.tres's SETs were found")

	# "stat_id/priority" -> Array of "path (resource_name)"
	var slots: Dictionary = {}
	for entry in sets.values():
		var m: StatModifier = entry[0]
		var slot := "%s/%d" % [m.stat_id, m.priority]
		if not slots.has(slot):
			slots[slot] = []
		(slots[slot] as Array).append("%s (%s)" % [entry[1], m.resource_name])
	for slot in slots:
		var holders: Array = slots[slot]
		assert_eq(holders.size(), 1,
				"SET %s is authored more than once: %s — give each a distinct priority"
				% [slot, ", ".join(holders)])


func _collect_files(dir_path: String, out: Array[String]) -> void:
	if _SKIP_DIRS.has(dir_path.trim_suffix("/")):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_files(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.ends_with(".tres") or f.ends_with(".tscn"):
			out.append(dir_path.path_join(f))


func _walk(v: Variant, path: String, sets: Dictionary, seen: Dictionary) -> void:
	if v is Array:
		for e in v:
			_walk(e, path, sets, seen)
	elif v is Dictionary:
		for k in v:
			_walk(v[k], path, sets, seen)
	elif v is Resource and not (v is Script):
		var id := (v as Resource).get_instance_id()
		if seen.has(id):
			return
		seen[id] = true
		if v is StatModifier and (v as StatModifier).operation == StatModifier.Operation.SET:
			if not sets.has(id):
				sets[id] = [v, path]
		for prop in (v as Resource).get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and prop.name != "script":
				_walk((v as Resource).get(prop.name), path, sets, seen)
