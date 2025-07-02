extends Node
class_name GameRoot

#signal graph_rebuild_requested


@onready var level_manager: LevelManager = $LevelLayer
@onready var ui_root: Control = $UIRoot
#@onready var turn_manager: TurnManager = $TurnManager
#@onready var fade_layer: FadeLayer = $FadeLayer

#@onready var tree_graph: TreeGraph = null


var current_level: Node = null

func _ready() -> void:
	#Game.root = self
	#print_debug("[GameRoot]: Ready. Deferring `_start_game()`")
	print_debug("[GameRoot]: Ready.")
	#call_deferred("_start_game")

func _start_game() -> void:
	print_debug('[GameRoot]: Starting Game.')


#func load_level(scene_path: String) -> void:
	##if current_level:
		##level_manager.remove_child(current_level)
		##current_level.queue_free()
		##current_level = null
	#current_level = null
	#level_manager.load_level_async(scene_path)

#func _on_level_loaded(tree_graph: TreeGraph) -> void:
	#print_debug("[GameRoot]: Loaded level: %s" % tree_graph)
	## Assign globals
	#Game.tree_graph = tree_graph
	#Game.navigator = tree_graph.navigator
	## Game READY!
	#Game.game_ready.emit()

# --- Utility accessors ---
func get_active_entities() -> Array:
	if not current_level:
		return []
	return current_level.get_node("Entities").get_children()

## --- Turn manager hooks ---
#func start_turns():
	#turn_manager.start_turn_sequence()
	
