## Game singleton to manage game turns and other typical global stuff
extends Node
class_name GameManager


signal game_ready
signal game_over

signal turn_ended(for_entity: TreeEntity)
signal turn_started(for_entity: TreeEntity)

signal main_player_selected(new_player: Player)

#region GLOBALS
var root: GameRoot
var tree_graph: TreeGraph
var navigator: Navigator
var turn_manager: TurnManager
## The "Main Player" of this game instance
var player: Player
#endregion

const GAME_ROOT_SCENE: PackedScene = preload("res://scenes/game_root.tscn")

func _ready() -> void:
	# Kick off into your first scene
	start_game_with_level.call_deferred("res://levels/dev_level_tree_graph.tscn")


func start_game_with_level(level_path: String) -> void:
	# 1) Single fade to black
	#await SceneTransition.fade_out()
	SceneTransition.set_faded(true)

	# 2) (Re)Load the GameRoot scene
	var res = get_tree().change_scene_to_packed(GAME_ROOT_SCENE)
	assert(res == OK, 'Error changing root scene')
	
	# 3) Async load only the level
	var packed_level = await SceneLoader.load_scene_async(level_path)
	
	# 4) Set new root and wire it up as needed
	root = get_tree().current_scene as GameRoot
	_wire_game_root(root)
	
	# 5) Replace old level child under LevelLayer
	var level_instance = packed_level.instantiate()
	var level_layer = root.get_node("LevelLayer")
	level_layer.add_child(level_instance)
	
	# 6) Wire up the loaded level
	_wire_level(level_instance)

	# 7) All set!
	emit_signal("game_ready")

	# 8) Fade back in
	await SceneTransition.fade_in()

func _wire_game_root(game_root: GameRoot) -> void:
	assert(root, 'ROOT BAD MKAY')
	root = game_root

func _wire_level(level_instance: TreeGraph) -> void:
	tree_graph = level_instance
	navigator = tree_graph.get_node("Navigator")
	assert(navigator, 'Navigator missing')
	#navigator = tree_graph.navigator
	turn_manager = tree_graph.turn_manager
	root.current_level = level_instance
	
	# hook turn signals to global
	#turn_manager.connect("turn_started", self, "_on_turn_started") # TODO: not yet, maybe later
	#turn_manager.connect("turn_ended",   self, "_on_turn_ended")

	# Setup main player (like this.. for now)
	player = get_tree().get_first_node_in_group("players")
	if player:
		main_player_selected.emit(player)


func _on_game_ready() -> void:
	pass
	## TODO:
	#initialize_main_player()
	#validate_game_setup()
	#
	#turn_manager.request_turn_cycle()


func validate_game_setup() -> void:
	## TODO: use?
	#assert(player is Player, 'Game setup error: No Main Player!')
	#assert(player and player.is_node_ready(), 'Game setup error: Main Player is not yet ready!')
	
	#assert(tree_graph is TreeGraph, 'Game setup error: No TreeGraph!')
	#assert(tree_graph and tree_graph.is_node_ready(), 'Game setup error: TreeGraph is not yet ready!')
	
	assert(turn_manager is TurnManager, 'Game setup error: No TurnManager!')
	assert(turn_manager and turn_manager.is_node_ready(), 'Game setup error: TurnManager is not yet ready!')
	
	assert(navigator is Navigator, 'Game setup error: No Navigator!')
	assert(navigator and navigator.is_node_ready(), 'Game setup error: Navigator is not yet ready!')


func initialize_main_player(main_player: Player = null):
	## TODO: use?
	if player:
		return # Already initialized

	# If not given, take first result of global `players` group
	if not main_player:
		main_player = get_tree().get_first_node_in_group('players') as Player
	
	if main_player is Player:
		print('Player found: ', main_player)
		Game.player = main_player
		return
	elif player == null:
		print_debug("No players, cannot initialize main player.")
	else:
		print_debug("Found player but of incorrect type, cannot initialize main player.")
