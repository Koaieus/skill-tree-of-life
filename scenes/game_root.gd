class_name GameRoot
extends Node2D

## Composition root for a level: holds the live references that UIRoot (and
## future AI / save / debug consumers) compose against. Public fields are the
## level's contract — read-only by convention; GameRoot itself owns mutations.
##
## Subclasses populate level content via [method _setup_level], called between
## system wiring and turn start. Default behaviour expects a hand-authored
## scene with `%Player` already present (dev_sandbox style); procgen sandboxes
## override the hook to spawn the player after generation.

# Entities — `player` may be null until _setup_level() resolves it. The default
# hook tries to find a `%Player` unique-name node; subclasses can replace.
var player: Entity
@onready var graph: Graph = $Graph

# Systems
@onready var input_ctl: PlayerInputController = %PlayerInputController
@onready var allocation_system: AllocationSystem = %AllocationSystem
@onready var battle_system: BattleSystem = %BattleSystem
@onready var turn_manager: TurnManager = %TurnManager

# UI
@onready var ui_root: UIRoot = %UIRoot

# Camera — looked up rather than @onready'd because dev_sandbox.tscn names it
# "Camera" while procgen variants use "GraphCamera". One Camera2D descendant
# is assumed (warn otherwise so a stray editor camera doesn't silently win).
var camera: Camera2D

var attack_highlight: AttackHighlightOverlay
var attack_vfx: AttackVFX
var melee_preview: MeleePreview
var damage_number_layer: DamageNumberLayer


func _ready() -> void:
	_mount_attack_highlight()
	_mount_attack_vfx()
	_mount_melee_preview()
	_mount_damage_number_layer()
	# Inject the systems BattleSystem needs to commit attacks. Done in code
	# rather than via scene NodePaths so the runtime-spawned VFX node can be
	# wired the same way as the scene-tree allocation_system.
	battle_system.allocation_system = allocation_system
	battle_system.attack_vfx = attack_vfx
	battle_system.melee_preview = melee_preview

	camera = _resolve_camera()
	# _setup_level runs BEFORE ui_root.compose because compose reads
	# `player.stat_board` immediately — procgen sandboxes that spawn the
	# player here need the entity in place first.
	_setup_level()
	ui_root.compose(self)

	if player != null and turn_manager != null:
		player.initiative_current = 100.0
		turn_manager.start_turn(player)
	_focus_camera_on_player()


## Subclass hook. Default = pick up an existing `%Player` node from the scene
## (dev_sandbox shape). Procgen sandboxes override to run generation + spawn
## entities, then assign `self.player`.
func _setup_level() -> void:
	if has_node("%Player"):
		player = get_node("%Player") as Entity


func _focus_camera_on_player() -> void:
	if camera == null or player == null:
		return
	var target: Vector2 = player.core_location.global_position if player.core_location != null else player.position
	camera.position = target


func _resolve_camera() -> Camera2D:
	for c in find_children("*", "Camera2D", true, false):
		return c as Camera2D
	return null


func _mount_attack_highlight() -> void:
	attack_highlight = AttackHighlightOverlay.new()
	attack_highlight.battle_system = battle_system
	attack_highlight.graph = graph
	graph.add_child(attack_highlight)


func _mount_attack_vfx() -> void:
	attack_vfx = AttackVFX.new()
	graph.add_child(attack_vfx)


func _mount_melee_preview() -> void:
	melee_preview = MeleePreview.new()
	melee_preview.battle_system = battle_system
	graph.add_child(melee_preview)


func _mount_damage_number_layer() -> void:
	damage_number_layer = DamageNumberLayer.new()
	graph.add_child(damage_number_layer)
