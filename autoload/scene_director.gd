extends Node

## Sole scene-change API: fade + threaded load + fade back in.
## Absorbs SceneLoader's load_threaded_request polling; SceneTransition stays
## the pure visual layer (fade animations + progress bar).

signal scene_changing(from: Node, to: String)
signal scene_ready(root: Node)

## How long to wait for a scene to declare itself presentable before revealing
## it regardless. Only a genuinely stuck scene reaches it.
const REVEAL_TIMEOUT_S := 30.0

var _history: Array[String] = []


func goto(scene: Variant, _ctx: Dictionary = {}) -> void:
	var path := _resolve_path(scene)
	if path.is_empty():
		push_error("SceneDirector.goto: could not resolve scene %s" % [scene])
		return

	var current := get_tree().current_scene
	var from_path := (current.scene_file_path if current else "")
	scene_changing.emit(current, path)

	await SceneTransition.fade_out()

	var result := ResourceLoader.load_threaded_request(path, "PackedScene", true)
	if result != OK:
		push_error("SceneDirector.goto: failed to start loading %s: %s" % [path, result])
		# The curtain no longer lowers itself (see [SceneTransition]), so every
		# bail-out after `fade_out` owes the player their screen back.
		await SceneTransition.fade_in()
		return

	var packed: PackedScene = await _await_load(path)

	if packed == null:
		push_error("SceneDirector.goto: failed to load %s" % [path])
		await SceneTransition.fade_in()
		return

	if not from_path.is_empty():
		_history.push_back(from_path)

	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame

	var root := get_tree().current_scene
	scene_ready.emit(root)
	# The curtain is still up here, and deliberately: `change_scene_to_packed`
	# gives us a root whose `_ready` may be a coroutine that is only getting
	# started (a level generates its graph over many frames). Revealing one
	# frame in showed the HUD over an empty world, then the world popping in.
	#
	# A root that knows when it is presentable says so with `is_reveal_ready`
	# and lowers its own curtain when it gets there (see [GameRoot]); we only
	# wait for it, with a bound so a run that never becomes ready — a client
	# still waiting on a host `run_setup` that never arrives — ends up looking
	# at something rather than at black forever.
	if root != null and root.has_method("is_reveal_ready"):
		if await _await_reveal(root):
			return
	await SceneTransition.fade_in()


func reload_current(ctx: Dictionary = {}) -> void:
	var current := get_tree().current_scene
	if current == null or current.scene_file_path.is_empty():
		push_error("SceneDirector.reload_current: no current scene to reload")
		return
	goto(current.scene_file_path, ctx)


func back() -> void:
	if _history.is_empty():
		return
	var path: String = _history.pop_back()
	goto(path)


## Poll the new root until it reveals itself, or [constant REVEAL_TIMEOUT_S]
## passes. Returns true when the scene owns the reveal from here (it reported
## ready and either faded in or is mid-fade), false when the caller should
## lower the curtain itself.
func _await_reveal(root: Node) -> bool:
	# Wall clock, not accumulated `get_process_delta_time()`: SceneTransition and
	# this director are both PAUSABLE (see `ui/pause_menu.gd`'s note), and a
	# timeout that stops counting while the tree is frozen is no timeout.
	var started := Time.get_ticks_msec()
	while not root.is_reveal_ready():
		await get_tree().process_frame
		# A scene swap under us (a level that routes straight back out) leaves
		# `root` freed; nothing left to wait for.
		if not is_instance_valid(root) or root != get_tree().current_scene:
			return false
		if Time.get_ticks_msec() - started >= int(REVEAL_TIMEOUT_S * 1000.0):
			push_warning("SceneDirector: %s never reported ready after %.0fs — revealing anyway"
					% [root.name, REVEAL_TIMEOUT_S])
			return false
	# Ready: the scene lowers its own curtain (or already has). Only step in if
	# it somehow left the screen covered without a fade running.
	return SceneTransition.is_fading() or not SceneTransition.is_curtain_up()


func _await_load(path: String) -> PackedScene:
	while true:
		await get_tree().process_frame
		var prog: Array = []
		var loading_status := ResourceLoader.load_threaded_get_status(path, prog)
		if loading_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Deliberately NOT pushed to the progress bar. Loading one `.tscn`
			# is not the wall-clock a player waits on (procgen is), it reports
			# 0..1 against a bar that reads 0..100, and a bar that runs to full
			# and then snaps back to 0 for the real work reads as a bug.
			continue
		if loading_status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path)
		push_error("SceneDirector: threaded load failed for %s" % path)
		return null
	return null


func _resolve_path(scene: Variant) -> String:
	if scene is String:
		return scene
	if scene is StringName:
		return String(scene)
	if scene is PackedScene:
		return scene.resource_path
	return ""
