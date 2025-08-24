extends Node
class_name GameRoot

#signal graph_rebuild_requested

var main_player: Player

@onready var turn_manager: TurnManager = $TurnManager
@onready var navigator: Navigator = $Navigator
@onready var level_layer: LevelManager = $LevelLayer
@onready var ui: Control = %UIRoot

var current_level: SkillGraphWorld = null

func _ready() -> void:
	#Game.root = self
	#print_debug("[GameRoot]: Ready. Deferring `_start_game()`")
	print_debug("[GameRoot]: Ready.")
	#call_deferred("_start_game")

func _start_game() -> void:
	print_debug('[GameRoot]: Starting Game.')
	

func start_with_level(level_path: String) -> void:
	_set_globals()
	# Pass the job of loading to LevelManager
	await level_layer.load_from_skill_graph_edit(level_path)
	
	# Once level is loaded, set up players/entities
	_init_players()
	#_init_turns()

	# Notify GameManager that we’re good to go
	Game.game_started.emit(self)


func _init_players() -> void:
	# For now, 1P assumption
	var player := Player.new()
	Game.skill_graph_world.players.add_child(player)
	main_player = player

	# Find starter skills
	var starters = get_tree().get_nodes_in_group("starter-skills")

	match starters.size():
		0:
			push_error("No starter skills found! Can't start game.")
		1:
			# Auto-pick if there’s exactly one
			_assign_starter(player, starters[0])
		_:
			# More than one: enter a "selection phase"
			assert(false, 'ToDo support multiple starting options')
			await _handle_starter_selection(player, starters)


func _assign_starter(player: Player, starter: SkillNode2D) -> void:
	player.core = starter
	starter.set_owner(player)
	starter.remove_from_group(&'starter-skills')
	#player.stats.apply_from_core(starter)


func _handle_starter_selection(player: Player, starters: Array) -> void:
	# Tell the UI: show all possible starters
	Game.ui.show_starter_options(starters)

	# Wait for the UI to emit "starter_chosen"
	var chosen: SkillNode2D = await ui.starter_chosen

	_assign_starter(player, chosen)


# --- Utility accessors ---
func get_active_entities() -> Array:
	if not current_level:
		return []
	return current_level.get_node("Entities").get_children()

## --- Turn manager hooks ---
#func start_turns():
	#turn_manager.start_turn_sequence()
	

func _set_globals() -> void:
	# Set globals:
	Game.root = self
	Game.navigator = navigator
	assert(navigator, 'Navigator missing')
	Game.turn_manager = turn_manager


func _on_level_layer_level_loaded(new_level: SkillGraphWorld) -> void:
	current_level = new_level
	Game.skill_graph_world = new_level
	print('LEVEL LOADED @ GAMEROOT: %s' % new_level)
