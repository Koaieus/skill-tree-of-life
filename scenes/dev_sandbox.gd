class_name GameRoot
extends Node2D

## Composition root for a level: holds the live references that UIRoot (and
## future AI / save / debug consumers) compose against. Public fields are the
## level's contract — read-only by convention; GameRoot itself owns mutations.

@onready var player: Entity = %Player
@onready var graph: Graph = $Graph
@onready var input_ctl: PlayerInputController = $Graph/PlayerInputController
@onready var battle_system: BattleSystem = $Graph/BattleSystem
@onready var turn_manager: TurnManager = $Graph/TurnManager
@onready var ui_root: UIRoot = $UI/UIRoot

var attack_highlight: AttackHighlightOverlay


func _ready() -> void:
	ui_root.compose(self)
	_mount_attack_highlight()

	if player != null and turn_manager != null:
		player.initiative_current = 100.0
		turn_manager.start_turn(player)


func _mount_attack_highlight() -> void:
	attack_highlight = AttackHighlightOverlay.new()
	attack_highlight.battle_system = battle_system
	attack_highlight.graph = graph
	graph.add_child(attack_highlight)
