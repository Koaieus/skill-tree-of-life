extends Node2D

## Dev sandbox glue — wires the UI's stats panel to the player's stat board
## once both are in the tree. Lives here, not on the StatsPanel itself, so
## the panel stays a pure renderer (board in, labels out) and this scene
## owns the "who's the player?" decision.

@onready var _player: Entity = %Player
@onready var _ui_root: Control = $UI/UIRoot
@onready var _turn_manager: TurnManager = $Graph/TurnManager


func _ready() -> void:
	var stats_vbox: Node = _ui_root.find_child("StatsVBox", true, false)
	if stats_vbox != null and _player != null:
		stats_vbox.board = _player.stat_board

	var end_turn_btn := _ui_root.find_child("EndTurnButton", true, false) as Button
	if end_turn_btn != null:
		end_turn_btn.pressed.connect(_on_end_turn_pressed)

	# Kick off the first turn so the start-of-turn upkeep (XP tick + AP/DP
	# refill) actually fires. Player-only loop for the sandbox.
	if _turn_manager != null and _player != null:
		_turn_manager.start_turn(_player)


func _on_end_turn_pressed() -> void:
	if _turn_manager == null or _player == null:
		return
	if _turn_manager.current_entity != null:
		_turn_manager.end_turn()
	_turn_manager.start_turn(_player)
