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

## Loading a level `.tscn` pulls its shader sub-resources, and the headless
## dummy renderer logs `!actions.custom_samplers.has(...)` while compiling one
## of them — an engine error GUT would otherwise count as a failure of whichever
## test loaded that scene first (so this script was red alone and green in a
## sharded suite purely by load order). Nothing here asserts on rendering: this
## is a resource census, so engine errors are not failures for its duration.
var _engine_errors_were: GutUtils.TREAT_AS


func before_all() -> void:
	_engine_errors_were = gut.error_tracker.treat_engine_errors_as
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func after_all() -> void:
	gut.error_tracker.treat_engine_errors_as = _engine_errors_were


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


## The pairing above is one symptom; the disease is the inline copy itself.
## A scene node's `stat_board` must be a `.tres` on disk (the default board,
## or an authored sparse one for a blocker) — an inline `[sub_resource]` is a
## snapshot that stops following the default the day it is pasted
## (godot-scene-authoring rule; dev_sandbox's had rotted to 16 missing fields).
func test_no_scene_carries_an_inline_entity_board() -> void:
	var inline: Array[String] = []
	for board_path in _authored_boards():
		if not (board_path[0] as String).contains("::"):
			continue
		var board: EntityStatBoard = board_path[1]
		if board.resource_path.is_empty() or board.resource_path.contains("::"):
			inline.append(board_path[0])
	assert_eq(inline, [], "scene nodes whose stat_board is an inline copy instead of a .tres")


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
