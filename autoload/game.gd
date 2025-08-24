## Game singleton to manage game turns and other typical global stuff
extends Node
class_name GameManager


signal game_ready
signal game_started
signal game_over

signal turn_ended(for_entity: TreeEntity)
signal turn_started(for_entity: TreeEntity)

signal main_player_selected(new_player: Player)

signal node_pressed(node: SkillNode2D)
signal node_pressed_right(node: SkillNode2D)

#region GLOBALS
var root: GameRoot
var skill_graph_world: SkillGraphWorld # inside LevelLayer
var navigator: Navigator
var turn_manager: TurnManager
## The "Main Player" of this game instance
var player: Player
#endregion

const GAME_ROOT_SCENE: PackedScene = preload("res://scenes/game_root.tscn")

func _ready() -> void:
	# Kick off into your first scene
	start_game_with_level("res://levels/dev_graph_level.tscn")


func start_game_with_level(level_path: String) -> void:
	# 1) Single fade to black
	#await SceneTransition.fade_out()
	SceneTransition.set_faded(true)

	# 2) (Re)Load the GameRoot scene
	var res = get_tree().change_scene_to_packed(GAME_ROOT_SCENE)
	assert(res == OK, 'Error changing root scene')
	
	# 3) Async load only the level
	var packed_level = await SceneLoader.load_scene_async(level_path)
	await get_tree().process_frame
	# 4) Set new root and wire it up as needed
	root = get_tree().current_scene as GameRoot
	assert(root, 'No root found')
	_wire_game_root(root)
	
	# 5) Instantiate the loaded level and use it as data source for constructing the graph
	var level_data_source: SkillGraphEdit = packed_level.instantiate()
	
	skill_graph_world = preload("res://graph/skill_graph_world.tscn").instantiate()
	#skill_graph_world = root.level_layer.skill_graph_world
	assert(skill_graph_world is SkillGraphWorld, 'No SkillGraphWorld: %s' % skill_graph_world)
	root.level_layer.add_child(skill_graph_world)
	_wire_level(skill_graph_world)
	# Read SkillGraphEdit as datasource to populate new SkillGraphWorld instance
	SkillGraphEditParser.populate_world_from_edit(level_data_source, skill_graph_world)
	
	# 6) All set!
	start_game()

	# 7) Fade back in
	await SceneTransition.fade_in()

func _wire_game_root(game_root: GameRoot) -> void:
	assert(game_root, 'ROOT BAD MKAY')
	# Set globals:
	root = game_root
	navigator = root.navigator
	assert(navigator, 'Navigator missing')
	turn_manager = root.turn_manager

func _wire_level(level_instance: SkillGraphWorld) -> void:
	root.current_level = level_instance
	skill_graph_world = level_instance
	
	## hook turn signals to global
	##turn_manager.connect("turn_started", self, "_on_turn_started") # TODO: not yet, maybe later
	##turn_manager.connect("turn_ended",   self, "_on_turn_ended")
#
	## Setup main player (like this.. for now)
	#player = get_tree().get_first_node_in_group("players")
	#if player:
		#main_player_selected.emit(player)

func start_game() -> void:

	initialize_main_player()
	pick_and_allocate_starting_skills()
	await get_tree().process_frame
	#validate_game_setup()
	turn_manager.request_turn_cycle()
	game_started.emit()


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
	assert(player == null, 'Player already set')

	# If not given, take first result of global `players` group
	if not main_player:
		main_player = get_tree().get_first_node_in_group('players') as Player
	assert(main_player, 'Found no player to assign')
	
	if main_player is Player:
		print('Player found: ', main_player)
		Game.player = main_player
		return
	elif player == null:
		print_debug("No players, cannot initialize main player.")
	else:
		print_debug("Found player but of incorrect type, cannot initialize main player.")

func pick_and_allocate_starting_skills() -> void:
	for pl in get_tree().get_nodes_in_group(&'players'):
		var starter_skill := _pick_player_starting_skill(pl)
		Game.root.current_level.add_entity(pl, starter_skill)
		starter_skill.remove_from_group(&'starter-skills')

func _pick_player_starting_skill(_player: Player) -> SkillNode2D:
	match get_tree().get_node_count_in_group(&'starter-skills'):
		0:
			assert(false, 'No starter skills available')
		1:
			# One choice, easy
			return get_tree().get_first_node_in_group(&'starter-skills')
		_:
			assert(false, 'ToDo: handle multiple starter skills available')
			return get_tree().get_first_node_in_group(&'starter-skills')
	return null
