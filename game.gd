## Game singleton to manage game turns and other typical global stuff
extends Node
class_name GameManager

signal game_ready
signal turn_ended(for_entity: TreeEntity)
signal turn_started(for_entity: TreeEntity)
signal player_selected(new_player: Player)
#signal player_stats_changed(new_stats: Stats)


@export var tree_graph: TreeGraph
@export var navigator: Navigator
@export var turn_manager: TurnManager

## The "Main Player" of this game instance
@export var player: Player:
	get():
		return player
	set(v):
		if v and player != v:
			player = v
			print('aaaaaaaaaaaaaaaaaaaaaaaaa')
			player_selected.emit(player)
			#player.stats.stats_changed.connect(
				#func(stats: Stats):
					#print('BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB')
					##player_stats_changed.emit(stats)
			#)


func _on_game_ready() -> void:
	initialize_main_player()
	validate_game_setup()
	
	turn_manager.request_turn_cycle()


## Readonly version of the entity that currently has the turn
var entity_at_turn: TreeEntity:
	get():
		return turn_manager.entity_at_turn

## Checks whether any entity currently has the turn
func has_turn(test_entity: TreeEntity) -> bool:
	if not test_entity \
	   or not turn_manager \
	   or not turn_manager.entity_at_turn:
		return false
	return turn_manager.entity_at_turn == test_entity

## Ends turn for entity that currently has the turn
func end_turn() -> void:
	print('[GAME] ENDING TURN!')
	
	turn_manager.turn_ended.emit()
		
	## Add current entity to back of turn order
	#turn_order.push_back(_entity_at_turn)
	## Get next entity in turn order list, skipping ones that are NULL
	#var next: TreeEntity = null
	#while not next:
		#next = turn_order.pop_front()
	#_entity_at_turn = next


## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#

## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass

	
	
func validate_game_setup() -> void:
	
	assert(player is Player, 'Game setup error: No Main Player!')
	assert(player and player.is_node_ready(), 'Game setup error: Main Player is not yet ready!')
	
	assert(tree_graph is TreeGraph, 'Game setup error: No TreeGraph!')
	assert(tree_graph and tree_graph.is_node_ready(), 'Game setup error: TreeGraph is not yet ready!')
	
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
