extends Node
class_name GameRoot

#signal graph_rebuild_requested


@onready var turn_manager: TurnManager = $TurnManager
@onready var navigator: Navigator = $Navigator
@onready var level_layer: LevelManager = $LevelLayer
@onready var ui_root: Control = %UIRoot

var current_level: SkillGraphWorld = null

func _ready() -> void:
	#Game.root = self
	#print_debug("[GameRoot]: Ready. Deferring `_start_game()`")
	print_debug("[GameRoot]: Ready.")
	#call_deferred("_start_game")

func _start_game() -> void:
	print_debug('[GameRoot]: Starting Game.')
	


# --- Utility accessors ---
func get_active_entities() -> Array:
	if not current_level:
		return []
	return current_level.get_node("Entities").get_children()

## --- Turn manager hooks ---
#func start_turns():
	#turn_manager.start_turn_sequence()
	
