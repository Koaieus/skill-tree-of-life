## Game singleton to manage game turns and other typical global stuff
extends Node
class_name GameManager


signal game_ready
signal game_over

signal turn_ended(for_entity: TreeEntity)
signal turn_started(for_entity: TreeEntity)

signal main_player_selected(new_player: Player)

#region GLOBALS
var current_root: Node
var tree_graph: TreeGraph
var navigator: Navigator
var turn_manager: TurnManager
## The "Main Player" of this game instance
var player: Player
#endregion

func _ready() -> void:
	Kick off into your first scene
	goto_game_root()


# --------------------------------------------------
# 1) GameRoot phase
# --------------------------------------------------

func goto_game_root() -> void:
	# swap in GameRoot scene
	await _swap_scene("res://scenes/GameRoot.tscn")
	# now current_root references the GameRoot instance
	_wire_game_root(current_root)
	emit_signal("game_root_ready", current_root)

func _wire_game_root(game_root: GameRoot) -> void:
	current_root = game_root
	# You can now reference LevelLayer, Transition, Loader, etc. via current_root if necessary
	# (e.g. `root.get_node("LevelLayer")` later in level phase)
	# No TreeGraph or Navigator here yet

# --------------------------------------------------
# 2) Level phase
# --------------------------------------------------

func load_level(path: String) -> void:
	# 2a) fade out
	await Transition.fade_out()
	# 2b) async load
	var packed_scene: PackedScene = await Loader.load_scene_async(path)
	# 2c) insert under LevelLayer
	var level_layer: Node = current_root.get_node("LevelLayer")
	# clear any previous level
	for c in level_layer.get_children():
		c.queue_free()
	current_level = packed_scene.instantiate()
	level_layer.add_child(current_level)
	# 2d) wire only after it's in the tree
	_wire_level(current_level)
	emit_signal("level_ready", current_level)
	# 2e) fade back in
	await Transition.fade_in()

func _wire_level(new_tree_graph: TreeGraph) -> void:
	# Get the Navigator & TurnManager children (by type, not name)
	var navigator: Navigator = tree_graph.get_node("Navigator")
	var turn_manager: TurnManager = tree_graph.get_node("TurnManager")

	# assign to global Game for easy access
	tree_graph    = new_tree_graph
	navigator     = navigator
	turn_manager  = turn_manager

	# broker Navigator → TreeGraph
	navigator.set_graph(tree_graph)

	# hook turn signals to global
	#turn_manager.connect("turn_started", self, "_on_turn_started")
	#turn_manager.connect("turn_ended",   self, "_on_turn_ended")

	# (Player wiring can come later once you choose how to place/identify it)
	player = get_tree().get_first_node_in_group("players")

# --------------------------------------------------
# Scene swap helper
# --------------------------------------------------

func change_root_scene(path: String) -> void:
	# 1) fade out any existing visuals
	await SceneTransition.fade_out()

	# 2) async‑load the next scene’s PackedScene
	var packed: PackedScene = await SceneLoader.load_scene_async(path, SceneTransition.set_progress)
	assert(packed != null, "Failed to load %s!" % path)

	# 3) hand it off to Godot’s scene‑tree swapper
	var err = get_tree().change_scene_to_packed(packed)
	assert(err == OK, "Failed to change_scene_to_packed: %s" % err)

	# 4) fade back in once the new scene is fully active
	await SceneTransition.fade_in()

func _swap_scene(path: String) -> void:
	# fade out current
	await SceneTransition.fade_out()

	# remove old root
	if current_root:
		current_root.queue_free()
		current_root = null

	# load new root
	var packed: PackedScene = await SceneLoader.load_scene_async(path)
	current_root = packed.instantiate()
	get_tree().root.add_child(current_root)

	# fade in new root
	await SceneTransition.fade_in()


func _on_game_ready() -> void:
	pass
	#initialize_main_player()
	#validate_game_setup()
	#
	#turn_manager.request_turn_cycle()


func validate_game_setup() -> void:
	
	#assert(player is Player, 'Game setup error: No Main Player!')
	#assert(player and player.is_node_ready(), 'Game setup error: Main Player is not yet ready!')
	
	#assert(tree_graph is TreeGraph, 'Game setup error: No TreeGraph!')
	#assert(tree_graph and tree_graph.is_node_ready(), 'Game setup error: TreeGraph is not yet ready!')
	
	assert(turn_manager is TurnManager, 'Game setup error: No TurnManager!')
	assert(turn_manager and turn_manager.is_node_ready(), 'Game setup error: TurnManager is not yet ready!')
	
	assert(navigator is Navigator, 'Game setup error: No Navigator!')
	assert(navigator and navigator.is_node_ready(), 'Game setup error: Navigator is not yet ready!')


func initialize_main_player(main_player: Player = null):
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

## OLD CRAP:

### Checks whether any entity currently has the turn
#func has_turn(test_entity: TreeEntity) -> bool:
	#if not test_entity \
	   #or not turn_manager \
	   #or not turn_manager.entity_at_turn:
		#return false
	#return turn_manager.entity_at_turn == test_entity

### Ends turn for entity that currently has the turn
#func end_turn() -> void:
	#print('[GAME] ENDING TURN!')
	#
	#turn_manager.turn_ended.emit()
		#
	### Add current entity to back of turn order
	##turn_order.push_back(_entity_at_turn)
	### Get next entity in turn order list, skipping ones that are NULL
	##var next: TreeEntity = null
	##while not next:
		##next = turn_order.pop_front()
	##_entity_at_turn = next


## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#

## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass

	
