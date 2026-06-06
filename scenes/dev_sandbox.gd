extends Node2D

## Dev sandbox glue — wires the UI's stats panel to the player's stat board
## once both are in the tree. Lives here, not on the StatsPanel itself, so
## the panel stays a pure renderer (board in, labels out) and this scene
## owns the "who's the player?" decision.

@onready var _player: Entity = %Player
@onready var _ui_root: Control = $UI/UIRoot


func _ready() -> void:
	var stats_vbox: Node = _ui_root.find_child("StatsVBox", true, false)
	if stats_vbox != null and _player != null:
		stats_vbox.board = _player.stat_board
