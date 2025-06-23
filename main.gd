extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print('[MAIN] Signalling `game_ready`!')
	Game.game_ready.emit()
	#start_game()

## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass

#func start_game() -> void:
	#initialize_current_turn()
#
#func initialize_current_turn():
	#if Game.entity_at_turn:
		#return # Already initialized
	#var entity: TreeEntity = get_tree().get_first_node_in_group('players') as TreeEntity
	#
	#if entity is TreeEntity:
		##print('Entity found: ', player)
		#Game._entity_at_turn = entity
		#return
	#print_debug("No entities, cannot initialize current turn.")
#
#
#
#func _on_players_child_exiting_tree(node: Node) -> void:
	#if node is TreeEntity:
		#initialize_current_turn()
#
#func _on_players_child_entered_tree(node: Node) -> void:
	#if node is TreeEntity and not Game.entity_at_turn:
		#initialize_current_turn()
