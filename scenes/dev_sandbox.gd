class_name GameRoot
extends Node2D

## Composition root for a level: holds the live references that UIRoot (and
## future AI / save / debug consumers) compose against. Public fields are the
## level's contract — read-only by convention; GameRoot itself owns mutations.

@onready var player: Entity = %Player
@onready var input_ctl: PlayerInputController = $Graph/PlayerInputController
@onready var battle_system: BattleSystem = $Graph/BattleSystem
@onready var turn_manager: TurnManager = $Graph/TurnManager
@onready var ui_root: UIRoot = $UI/UIRoot


func _ready() -> void:
	ui_root.compose(self)

	if player != null and turn_manager != null:
		player.initiative_current = 100.0
		turn_manager.start_turn(player)
