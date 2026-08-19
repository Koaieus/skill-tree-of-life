extends Node

## Sole scene-change API: fade + threaded load + fade back in.
## Absorbs SceneLoader's load_threaded_request polling; SceneTransition stays
## the pure visual layer (fade animations + progress bar).

signal scene_changing(from: Node, to: String)
signal scene_ready(root: Node)

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
		return

	var packed: PackedScene = await _await_load(path)

	if packed == null:
		push_error("SceneDirector.goto: failed to load %s" % [path])
		return

	if not from_path.is_empty():
		_history.push_back(from_path)

	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame

	var root := get_tree().current_scene
	scene_ready.emit(root)
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


func _await_load(path: String) -> PackedScene:
	while true:
		await get_tree().process_frame
		var prog: Array = []
		var loading_status := ResourceLoader.load_threaded_get_status(path, prog)
		if loading_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not prog.is_empty():
				SceneTransition.set_progress(prog[0])
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
