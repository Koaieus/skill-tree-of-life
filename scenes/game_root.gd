extends Node
class_name GameRoot

@onready var level_container: Node = $LevelContainer
@onready var ui_root: Control = $UIRoot
@onready var turn_manager: Node = $TurnManager
@onready var tree_graph = $TreeGraph


var current_level: Node = null

func _ready() -> void:
	print_debug("[GameRoot]: Ready.")
	Game.game_ready.emit()  # Notify Game.gd autoload

# --- Level loading ---
func load_level(scene_path: String) -> void:
	if current_level:
		level_container.remove_child(current_level)
		current_level.queue_free()
		current_level = null

	var scene: PackedScene = load(scene_path)
	current_level = scene.instantiate()
	level_container.add_child(current_level)
	print_debug("[GameRoot]: Loaded level: %s" % scene_path)

# --- Utility accessors ---
func get_active_entities() -> Array:
	if not current_level:
		return []
	return current_level.get_node("Entities").get_children()

# --- Turn manager hooks ---
func start_turns():
	turn_manager.start_turn_sequence()
