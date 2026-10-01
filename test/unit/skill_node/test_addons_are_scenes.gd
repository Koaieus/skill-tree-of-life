extends GutTest

## An addon exists only as a scene: no `SkillNodeAddon` (or subclass) is ever
## built with `.new()`, and no script is ever `set_script`-ed onto a bare node to
## make one — not in shipped code, not in tests. A test instantiates a shipped
## scene under `skill_node/addons/defs/` or a fixture under `test/fixtures/addons/`.
## This is what lets an addon's kind be its scene path with no fallback.
##
## Walks every `.gd` under `res://`, skipping dot-directories (`.godot`, `.claude`,
## `.worktrees`, …) and `addons/gut`. Strict on comments too: a doc line naming
## `FooAddon.new()` as a live path is the same lie this guard exists to catch.

const _SELF := "res://test/unit/skill_node/test_addons_are_scenes.gd"
const _SKIP_DIRS: Array[String] = ["res://addons/gut"]


func test_no_addon_is_built_in_code() -> void:
	var new_call := RegEx.create_from_string("\\b\\w*Addon\\.new\\(")
	var set_script_call := RegEx.create_from_string("set_script\\(")
	var hits: Array[String] = []
	for path in _gd_files("res://"):
		if path == _SELF:
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i]
			var is_new := new_call.search(line) != null
			var is_set_script := set_script_call.search(line) != null \
					and line.to_lower().contains("addon")
			if is_new or is_set_script:
				hits.append("%s:%d  %s" % [path, i + 1, line.strip_edges()])
	assert_eq(hits.size(), 0,
			"addons are scenes — instantiate one, never .new()/set_script it:\n" + "\n".join(hits))


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		var sub_path := dir_path.path_join(sub)
		if sub_path in _SKIP_DIRS:
			continue
		out.append_array(_gd_files(sub_path))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out
