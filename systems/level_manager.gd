extends Control
class_name LevelManager

signal level_loaded(new_tree_graph: TreeGraph)
signal level_load_progress(pct: float)

var _current_level_scene: TreeGraph = null

var _loading_path: String = ""
var _is_loading: bool = false

func load_level_async(level_path: String):
	if _is_loading:
		return
	_is_loading = true
	_loading_path = level_path
	
	var ok = ResourceLoader.load_threaded_request(level_path, "PackedScene")
	if ok != OK:
		_reset()
		push_error("Failed to load level: [%s] %s" % [ok, level_path])
		return

	## Fade out
	#var fade = Game.root.fade_layer
	#fade.fade_out()
	#await fade.fade_completed
	
	if _current_level_scene:
		remove_child(_current_level_scene)
		_current_level_scene.queue_free()

	# Hook up global systems refs
	#Game.tree_graph = _current_level_scene
	#Game.navigator = _current_level_scene.navigator
	#Game.turn_manager = _current_level_scene.turn_manager

	#await get_tree().process_frame
	#fade.fade_in()
	
	return level_loaded

func _reset() -> void:
	_is_loading = false
	_loading_path = ""

func _process(delta: float) -> void:
	if not _is_loading:
		return

	var prog := []                                   # must be a distinct Array
	var status := ResourceLoader.load_threaded_get_status(_loading_path, prog)
	level_load_progress.emit(prog[0])

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			_complete_loading()
			return _reset()
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error('Error while loading level %s: invalid resource' % _loading_path)
			return _reset()
		ResourceLoader.THREAD_LOAD_FAILED:
			push_error('Error while loading level: loading failed' % _loading_path)
			return _reset()

func _complete_loading() -> void:
	var packed : PackedScene = ResourceLoader.load_threaded_get(_loading_path)
	_current_level_scene = packed.instantiate()
	add_child(_current_level_scene)
	level_loaded.emit(_current_level_scene)
	#var fade = Game.root.fade_layer
	#fade.fade_in()
