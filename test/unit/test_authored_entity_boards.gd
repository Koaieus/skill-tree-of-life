extends GutTest

## Hand-authored [EntityStatBoard]s drift. Each one starts as a copy of
## `entity/default_entity_board.tres` (Entity duplicates its board on `_ready`,
## and an editor save bakes that copy back into the scene — see
## .claude/rules/godot-scene-authoring.md), and then the default grows a stat
## the copy never gets.
##
## The copy that motivated this walked into a real bug: `dev_sandbox.tscn`'s two
## boards predated the `level` stat (#200), so `Entity._on_xp_replenished` found
## `stat_board.level == null`, skipped the bump, and every level readout — the
## Hero Sigil badge, the XP track's LEVEL label — sat at 1 for the whole run
## while XP filled and skill points minted.
##
## The invariant is the pairing, not the field: a board that can EARN xp must be
## able to record what that xp bought. A sparse board with neither (a blocker)
## is fine.

const _SCENE_ROOTS: Array[String] = ["res://scenes", "res://entity"]


func test_every_authored_entity_board_that_has_xp_also_has_level() -> void:
	var checked := 0
	for board_path in _authored_boards():
		var board: EntityStatBoard = board_path[1]
		checked += 1
		if board.xp == null:
			continue
		assert_not_null(board.level,
			"%s carries an `xp` pool but no `level` stat — it can gain XP it can never record" % board_path[0])
	assert_gt(checked, 0, "the walk found no authored entity boards at all — it stopped walking")


## Every authored EntityStatBoard reachable from a scene or a `.tres` under
## [constant _SCENE_ROOTS], as `[where, board]` pairs. Scenes are read through
## [SceneState] rather than instantiated: a level scene's `_ready` builds a
## whole world, and this only needs the authored property.
func _authored_boards() -> Array:
	var out: Array = []
	for root in _SCENE_ROOTS:
		for path in _files_under(root):
			if path.ends_with(".tres"):
				var res := load(path)
				if res is EntityStatBoard:
					out.append([path, res])
			elif path.ends_with(".tscn"):
				var packed := load(path) as PackedScene
				if packed == null:
					continue
				var state := packed.get_state()
				for n in state.get_node_count():
					for p in state.get_node_property_count(n):
						if state.get_node_property_name(n, p) != &"stat_board":
							continue
						var value = state.get_node_property_value(n, p)
						if value is EntityStatBoard:
							out.append(["%s::%s" % [path, state.get_node_name(n)], value])
	return out


func _files_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_files_under(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir_path.path_join(f))
	return out
