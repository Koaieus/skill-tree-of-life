extends GutTest
## Gate for .claude/rules/gdscript-pitfalls.md: a script the engine loads from a
## .tres/.tscn the editor opens must be @tool, else it is a placeholder there.

const DIRS: Array[String] = [
	"res://effects", "res://attack/ammo", "res://attack/outcome",
	"res://ui/vfx/coordinator", "res://entity", "res://stats_system/defs",
]


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tres") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		_collect(dir.path_join(d), out)


func _is_tool(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.is_empty() or s.begins_with("#"):
			continue
		return s.begins_with("@tool")
	return false


func test_scripts_loaded_from_resources_are_tool() -> void:
	var files: Array[String] = []
	for d in DIRS:
		_collect(d, files)
	var rx := RegEx.create_from_string('\\[ext_resource[^\\]]*type="Script"[^\\]]*path="([^"]+)"')
	var offenders := {}
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		for m in rx.search_all(text):
			var sp := m.get_string(1)
			if sp.ends_with(".gd") and not offenders.has(sp) and not _is_tool(sp):
				offenders[sp] = f
	var names := offenders.keys()
	names.sort()
	assert_eq(names.size(), 0, "non-@tool scripts loaded from resources: %s" % [names])
