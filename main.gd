extends Node

@onready var players: Node = %Players

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	initialize_main_player()
	print('Signalling `game_ready`!')
	Global.game_ready.emit()
	start_game()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func start_game() -> void:
	initialize_current_turn()

func initialize_current_turn():
	if Global.entity_at_turn:
		return # Already initialized
	var entity: TreeEntity = get_tree().get_first_node_in_group('players')
	
	if entity is TreeEntity:
		#print('Entity found: ', player)
		Global._entity_at_turn = entity
		return
	print_debug("No entities, cannot initialize current turn.")

func initialize_main_player():
	if Global.player:
		return # Already initialized
	#for child in %Players.get_children():
	var player: Player = get_tree().get_first_node_in_group('players')
	
	if player is Player:
		print('Player found: ', player)
		Global.player = player
		return
	elif not player:
		print_debug("No players, cannot initialize main player.")
	else:
		print_debug("Found player but of incorrect type, cannot initialize main player.")


func _on_players_child_exiting_tree(node: Node) -> void:
	if node is TreeEntity:
		initialize_current_turn()

func _on_players_child_entered_tree(node: Node) -> void:
	if node is TreeEntity and not Global.entity_at_turn:
		initialize_current_turn()
