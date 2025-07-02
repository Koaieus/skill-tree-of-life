extends Node
class_name SceneLoaderManager

## Loaded as a singleton, it handles loading a PackedScene in async fasion
## based on the scene's resource path. Emits signals for progress and when done.


signal scene_loaded(scene: PackedScene)
signal loading_progress(progress: float)

enum LoadingStatus {IDLE, LOADING, FAILED, ABORTED, COMPLETE}

## Path of the scene currently being loaded
var _loading_path := ""
## The packed scene that is to be loaded
var _loaded_scene: PackedScene = null
## Error status while loading
var status: LoadingStatus = LoadingStatus.IDLE

## Called on loading progress with a float arg in [0, 1]
var _progress_callback: Callable


func _ready() -> void:
	set_process(false)


func load_scene_async(path: String, progress_callback := Callable()) -> Signal:
	assert(not is_processing(), "Cannot load scene `%s`: already loading scene `%s`" % [path, _loading_path])
	_loading_path = path
	_progress_callback = progress_callback
	_loaded_scene = null
	var result = ResourceLoader.load_threaded_request(path, "PackedScene", true)
	if result == OK:
		status = LoadingStatus.LOADING
		set_process(true)
	else:
		status = LoadingStatus.FAILED
		push_error('Error loading %s: %s' % [path, result])
		scene_loaded.emit.call_deferred(null)
	return scene_loaded


func _process(_delta):
	var prog : Array[float] = []
	var loading_status = ResourceLoader.load_threaded_get_status(_loading_path, prog)
	match loading_status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if _progress_callback.is_valid():
				_progress_callback.call(prog[0])
			loading_progress.emit(prog[0])
		ResourceLoader.THREAD_LOAD_LOADED:
			var scene: PackedScene = ResourceLoader.load_threaded_get(_loading_path)
			_loaded_scene = scene
			scene_loaded.emit(scene)
			status = LoadingStatus.COMPLETE
			set_process(false)
		ResourceLoader.THREAD_LOAD_FAILED:
			push_error("Failed to load scene: %s" % _loading_path)
			status = LoadingStatus.FAILED
			set_process(false)
			scene_loaded.emit(null)

func abort_loading() -> void:
	push_error("Failed to load scene `%s`: ABORTED" % _loading_path)
	status = LoadingStatus.ABORTED
	set_process(false)
	scene_loaded.emit(null)
