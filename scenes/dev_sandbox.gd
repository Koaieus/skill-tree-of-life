class_name GameRoot
extends Node2D

## Composition root for a level: holds the live references that UIRoot (and
## future AI / save / debug consumers) compose against. Public fields are the
## level's contract — read-only by convention; GameRoot itself owns mutations.

@onready var player: Entity = %Player
@onready var graph: Graph = $Graph
@onready var input_ctl: PlayerInputController = $Graph/PlayerInputController
@onready var allocation_system: AllocationSystem = $Graph/AllocationSystem
@onready var battle_system: BattleSystem = $Graph/BattleSystem
@onready var turn_manager: TurnManager = $Graph/TurnManager
@onready var ui_root: UIRoot = $UI/UIRoot

var attack_highlight: AttackHighlightOverlay
var attack_vfx: AttackVFX
var damage_number_layer: DamageNumberLayer


func _ready() -> void:
	ui_root.compose(self)
	_mount_attack_highlight()
	_mount_attack_vfx()
	_mount_damage_number_layer()
	# Inject the systems BattleSystem needs to commit attacks. Done in code
	# rather than via scene NodePaths so the runtime-spawned VFX node can be
	# wired the same way as the scene-tree allocation_system.
	battle_system.allocation_system = allocation_system
	battle_system.attack_vfx = attack_vfx

	if player != null and turn_manager != null:
		player.initiative_current = 100.0
		turn_manager.start_turn(player)


func _mount_attack_highlight() -> void:
	attack_highlight = AttackHighlightOverlay.new()
	attack_highlight.battle_system = battle_system
	attack_highlight.graph = graph
	graph.add_child(attack_highlight)


func _mount_attack_vfx() -> void:
	attack_vfx = AttackVFX.new()
	graph.add_child(attack_vfx)


func _mount_damage_number_layer() -> void:
	damage_number_layer = DamageNumberLayer.new()
	graph.add_child(damage_number_layer)
