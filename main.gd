extends Node

@onready var players: Node = %Players

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	initialize_main_player()
	start_game()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func start_game() -> void:
	initialize_current_turn()

func initialize_current_turn():
	if Global.entity_at_turn:
		return # Already initialized
	for child in %Players.get_children():
		if child is TreeEntity:
			Global._entity_at_turn = child
			return
	print_debug("No players, cannot initialize current turn.")

func initialize_main_player():
	if Global.player:
		return # Already initialized
	for player in %Players.get_children():
		if player is Player:
			Global.player = player
			return
	print_debug("No players, cannot initialize current turn.")


func _on_players_child_exiting_tree(node: Node) -> void:
	initialize_current_turn()

func _on_players_child_entered_tree(node: Node) -> void:
	initialize_current_turn()
