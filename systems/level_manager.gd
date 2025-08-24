extends Node
class_name LevelManager

signal level_loaded(new_level: SkillGraphWorld)
signal level_load_progress(pct: float)

var current_level: SkillGraphWorld = null

var _loading_path: String = ""
var _is_loading: bool = false


func load_from_skill_graph_edit(skill_graph_edit_path: String) -> void:
	var packed_level = await SceneLoader.load_scene_async(skill_graph_edit_path)
	var level_data_source: SkillGraphEdit = packed_level.instantiate()
	
	current_level = preload("res://graph/skill_graph_world.tscn").instantiate()
	#skill_graph_world = root.level_layer.skill_graph_world
	assert(current_level is SkillGraphWorld, 'No SkillGraphWorld: %s' % current_level)
	add_child(current_level)
	#_init_level(current_level)
	# Read SkillGraphEdit as datasource to populate new SkillGraphWorld instance
	SkillGraphEditParser.populate_world_from_edit(level_data_source, current_level)
	
	# 6) All set!
	level_loaded.emit(current_level)
	

### Starts loading a SkillGraphEdit scene asynchronously by resource path
### 		In _process the loading will be polled until completion, 
### 		after which the `level_loaded` signal is emitted with the instantiated scene
#func load_level_async(level_path: String):
	#assert(not _is_loading, 'Cannot load `%s`: already loading `%s`' % [level_path, _loading_path])
	#_is_loading = true
	#_loading_path = level_path
	#
	#var ok = ResourceLoader.load_threaded_request(level_path, "PackedScene")
	#if ok != OK:
		#_reset()
		#push_error("Failed to load level: [%s] %s" % [ok, level_path])
		#return
#
	### Fade out
	##var fade = Game.root.fade_layer
	##fade.fade_out()
	##await fade.fade_completed
#
	#if _current_level_scene:
		#remove_child(_current_level_scene)
		#_current_level_scene.queue_free()
#
	### Fade in
	##await get_tree().process_frame
	##fade.fade_in()
	#
	#return level_loaded
#
#func _reset() -> void:
	#_is_loading = false
	#_loading_path = ""
#
#func _process(delta: float) -> void:
	#if not _is_loading:
		#return
#
	#var prog := []                                   # must be a distinct Array
	#var status := ResourceLoader.load_threaded_get_status(_loading_path, prog)
	#level_load_progress.emit(prog[0])
#
	#match status:
		#ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			#return
		#ResourceLoader.THREAD_LOAD_LOADED:
			#_complete_loading()
			#return _reset()
		#ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			#push_error('Error while loading level %s: invalid resource' % _loading_path)
			#return _reset()
		#ResourceLoader.THREAD_LOAD_FAILED:
			#push_error('Error while loading level: loading failed' % _loading_path)
			#return _reset()
#
#func _complete_loading() -> void:
	#var packed : PackedScene = ResourceLoader.load_threaded_get(_loading_path)
	#_current_level_scene = packed.instantiate()
	#print("LEVEL LOADED @ LEVEL MANAGER: %s" % _current_level_scene)
	#add_child(_current_level_scene)
	#level_loaded.emit(_current_level_scene)
	##var fade = Game.root.fade_layer
	##fade.fade_in()
