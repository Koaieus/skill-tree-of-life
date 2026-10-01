extends GutTest

## Concrete addon scenes live under skill_node/addons/defs/, never directly
## under skill_node/addons/ (that folder holds only source + a base/template
## scene, which is never a .tscn).


func test_no_tscn_directly_under_addons_root() -> void:
	var dir := DirAccess.open("res://skill_node/addons")
	assert_not_null(dir, "res://skill_node/addons should exist")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			assert_false(
				entry.ends_with(".tscn"),
				"skill_node/addons/%s should have moved to skill_node/addons/defs/" % entry
			)
		entry = dir.get_next()
	dir.list_dir_end()


func test_every_defs_scene_has_skill_node_addon_root() -> void:
	var dir := DirAccess.open("res://skill_node/addons/defs")
	assert_not_null(dir, "res://skill_node/addons/defs should exist")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	var checked := 0
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tscn"):
			checked += 1
			var scene: PackedScene = load("res://skill_node/addons/defs/%s" % entry)
			var instance := scene.instantiate()
			assert_true(
				instance is SkillNodeAddon,
				"%s root should be a SkillNodeAddon" % entry
			)
			instance.free()
		entry = dir.get_next()
	dir.list_dir_end()
	assert_gt(checked, 0, "expected at least one concrete addon scene under defs/")
