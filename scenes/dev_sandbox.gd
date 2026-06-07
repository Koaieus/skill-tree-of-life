extends Node2D

## Dev sandbox glue — wires the UI's stats panel to the player's stat board
## once both are in the tree. Lives here, not on the StatsPanel itself, so
## the panel stays a pure renderer (board in, labels out) and this scene
## owns the "who's the player?" decision.

@onready var _player: Entity = %Player
@onready var _ui_root: UIRoot = $UI/UIRoot
@onready var _turn_manager: TurnManager = $Graph/TurnManager

var _end_turn_btn: Button


func _ready() -> void:
	var stats_vbox: StatsPanel = _ui_root.stats_v_box
	if stats_vbox != null and _player != null:
		stats_vbox.board = _player.stat_board

	_end_turn_btn = _ui_root.find_child("EndTurnButton", true, false) as Button
	if _end_turn_btn != null:
		_end_turn_btn.pressed.connect(_on_end_turn_pressed)

	if _turn_manager != null:
		_turn_manager.phase_changed.connect(_on_phase_changed)

	# Give the player full initiative so the first turn starts immediately
	# without ticking. TurnManager's _tick_until_ready() drives all subsequent turns.
	if _turn_manager != null and _player != null:
		_player.initiative_current = 100.0
		_turn_manager.start_turn(_player)


func _on_phase_changed(_entity: Entity, phase: TurnManager.Phase) -> void:
	if _end_turn_btn == null:
		return
	match phase:
		TurnManager.Phase.DEPLOYMENT:
			_end_turn_btn.text = "To Battle"
		TurnManager.Phase.BATTLE:
			_end_turn_btn.text = "Consolidate"
		TurnManager.Phase.CONSOLIDATION:
			_end_turn_btn.text = "End Turn"


func _on_end_turn_pressed() -> void:
	if _turn_manager == null or _turn_manager.current_entity == null:
		return
	if not _turn_manager.advance_phase():
		# advance_phase() returns false at CONSOLIDATION — actually end the turn.
		# TurnManager deducts initiative and auto-ticks until next entity is ready.
		_turn_manager.end_turn()
