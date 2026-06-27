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
##
## Spawning runtime entities: call [method spawn_entity] — it parents under
## `graph.entities_container`, duplicates the default stat board, and force-
## allocates a core if given. The hand-authored dev_sandbox `%Player` skips
## this path; that's fine, `%Player` lookup ignores parent.

const _DEFAULT_BOARD := preload("res://entity/default_entity_board.tres")

# Entities — `player` may be null until _setup_level() resolves it. The default
# hook tries to find a `%Player` unique-name node; subclasses can replace.
var player: Entity
@onready var graph: Graph = $Graph

# Systems
@onready var input_ctl: PlayerInputController = %PlayerInputController
@onready var allocation_system: AllocationSystem = %AllocationSystem
@onready var battle_system: BattleSystem = %BattleSystem
@onready var turn_manager: TurnManager = %TurnManager
@onready var vision_system: VisionSystem = %VisionSystem

# UI
@onready var ui_root: UIRoot = %UIRoot

# Camera — looked up rather than @onready'd because dev_sandbox.tscn names it
# "Camera" while procgen variants use "GraphCamera". One Camera2D descendant
# is assumed (warn otherwise so a stray editor camera doesn't silently win).
var camera: Camera2D

var highlight_controller: HighlightController
var node_highlight: NodeHighlightOverlay
var edge_highlight: EdgeHighlightOverlay
var attack_vfx: AttackVFX
var allocation_vfx: AllocationVFX
var melee_preview: MeleePreview
var floating_number_layer: FloatingNumberLayer


func _ready() -> void:
	_mount_highlight_controller()
	_mount_edge_highlight()
	_mount_node_highlight()
	_mount_attack_vfx()
	_mount_allocation_vfx()
	_mount_melee_preview()
	_mount_floating_number_layer()
	# Inject the systems BattleSystem needs to commit attacks. Done in code
	# rather than via scene NodePaths so the runtime-spawned VFX node can be
	# wired the same way as the scene-tree allocation_system.
	battle_system.allocation_system = allocation_system
	battle_system.graph = graph
	battle_system.attack_vfx = attack_vfx
	battle_system.melee_preview = melee_preview
	# Core-movement (#21) slide tween. The CoreMarker on `to_node` has already
	# popped in via Entity.core_location_changed; offset it to start at
	# `from_node` and glide back. Lives here rather than on Entity so SkillNode
	# stays the visual owner.
	allocation_system.core_moved.connect(_on_core_moved)
	# Entity death (#18): AllocationSystem strips the corpse's nodes off the same
	# bus signal; GameRoot owns the player-vs-NPC consequence (game-over / despawn).
	Events.entity_died.connect(_on_entity_died)

	camera = _resolve_camera()
	# Scene-authored ownership (dev_sandbox-style) must claim SP before
	# _setup_level runs — procgen spawning goes through force_allocate which
	# claims itself, but hand-authored owned_by= assignments skip that path.
	allocation_system.register_scene_authored_ownership()
	# _setup_level runs BEFORE ui_root.compose because compose reads
	# `player.stat_board` immediately — procgen sandboxes that spawn the
	# player here need the entity in place first. `await` is harmless on
	# synchronous overrides; procgen sandboxes that drive a loading bar
	# return a coroutine.
	await _setup_level()
	_assign_default_factions()
	# Invariant: every Entity must have an EntityController child so the
	# turn loop never stalls on an uncontrolled actor. Hand-authored
	# scenes (dev_sandbox, first_level_sandbox) historically forgot to
	# attach AIController to enemies; this defaulter is the catch-all
	# that keeps every sandbox playable without per-scene wiring.
	_ensure_controllers()
	ui_root.compose(self)

	if player != null and turn_manager != null:
		# Skip the initial tick race: fill the player's clock so they act first.
		# (start_turn clears the ready-group membership this would otherwise set.)
		if player.stat_board != null and player.stat_board.initiative != null:
			player.stat_board.initiative.restore_to_full()
		turn_manager.start_turn(player)
	_focus_camera_on_player()


## Entity death consequence (#18). Node-stripping is AllocationSystem's job (it
## also listens to `entity_died`); here we handle what's left: the player losing
## ends the run (game-over stub), an NPC dying despawns from the scene. The
## actual force-dealloc cascade + VFX already ran off the bus before this.
func _on_entity_died(entity: Entity) -> void:
	if entity == null:
		return
	if entity == player:
		_show_game_over()
	else:
		_despawn_npc(entity)


## Remove a dead NPC from the level. Pull it from the turn-loop groups
## SYNCHRONOUSLY so TurnManager's tick / _tick_until_ready skip it this frame —
## `queue_free` leaves the node valid (and group-resident) until frame end, so
## the group removal can't wait for it. Defensive: if the corpse somehow held
## the turn, clear `current_entity` so the loop isn't stalled on a freed actor.
##
## Free order is safe: AllocationSystem's death handler deallocates the corpse's
## nodes SYNCHRONOUSLY (off the same `entity_died` emit, before this runs), so
## `queue_free` here can't orphan them.
func _despawn_npc(entity: Entity) -> void:
	entity.remove_from_group(Entity.GROUP)
	entity.remove_from_group(Entity.READY_GROUP)
	if turn_manager != null and turn_manager.current_entity == entity:
		turn_manager.current_entity = null
	entity.queue_free()


## Game-over placeholder (#18). The full screen lives in the Metagame milestone;
## for now a dim overlay + label is enough to make player-death visible and stop
## the level reading as "still playable". Idempotent via the unique node name.
func _show_game_over() -> void:
	if has_node("GameOverStub"):
		return
	var layer := CanvasLayer.new()
	layer.name = "GameOverStub"
	layer.layer = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var label := Label.new()
	label.text = "GAME OVER"
	label.add_theme_font_size_override("font_size", 64)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(label)
	add_child(layer)


## Assigns `&"player"` faction to [member player]; leaves all other entities
## on their default (`&"npc"`). Future-proofs multi-faction filtering without
## changing today's `owned_by != attacker` hostility checks.
func _assign_default_factions() -> void:
	if player != null:
		player.faction = &"player"


## Attaches a default [EntityController] child to any [Entity] in the level
## that doesn't already have one. [PlayerController] for [member player];
## [AIController] for everyone else. No-op if the scene/code already wired
## a controller — explicit composition always wins.
func _ensure_controllers() -> void:
	for node in get_tree().get_nodes_in_group("entities"):
		var ent := node as Entity
		if ent == null:
			continue
		if _find_controller(ent) != null:
			continue
		var ctrl: EntityController
		if ent == player:
			ctrl = PlayerController.new()
			ctrl.name = "PlayerController"
		else:
			ctrl = AIController.new()
			ctrl.name = "AIController"
		ent.add_child(ctrl)


static func _find_controller(ent: Entity) -> EntityController:
	for child in ent.get_children():
		if child is EntityController:
			return child as EntityController
	return null


## Subclass hook. Default = pick up an existing `%Player` node from the scene
## (dev_sandbox shape). Procgen sandboxes override to run generation + spawn
## entities, then assign `self.player`.
func _setup_level() -> void:
	if has_node("%Player"):
		player = get_node("%Player") as Entity


## Spawn an [Entity] under `graph.entities_container` with a duplicated copy
## of the default stat board. If [param core_location] is given, force-allocates
## it as the entity's first node and sets `core_location`. If [param core_class]
## is given, assigns it as `core_class` so its modifier set + on_turn_started
## hook fire from Entity._ready. Returns the entity.
##
## Skips [method AllocationSystem.allocate] gating — this is dev/procgen
## setup, not a gameplay action. Mid-game spawning should still route through
## the gated path.
func spawn_entity(
	ent_name: String,
	color: Color,
	core_location: SkillNode = null,
	core_class: CoreClass = null,
	with_ai: bool = false,
) -> Entity:
	var ent := Entity.new()
	ent.name = ent_name
	ent.display_name = ent_name
	ent.color = color
	ent.stat_board = _DEFAULT_BOARD.duplicate(true) as StatBoard
	ent.core_class = core_class
	graph.entities_container.add_child(ent)
	if core_location != null:
		allocation_system.force_allocate(ent, core_location)
		ent.core_location = core_location
	if with_ai:
		var ai := AIController.new()
		ai.name = "AIController"
		ent.add_child(ai)
	return ent


func _on_core_moved(_entity: Entity, from_node: SkillNode, to_node: SkillNode) -> void:
	if to_node == null or from_node == null:
		return
	to_node.play_core_slide_from(from_node.global_position)


func _focus_camera_on_player() -> void:
	if camera == null or player == null:
		return
	var target: Vector2 = player.core_location.global_position if player.core_location != null else player.position
	camera.position = target


func _resolve_camera() -> Camera2D:
	for c in find_children("*", "Camera2D", true, false):
		return c as Camera2D
	return null


## Single active-provider arbiter for all highlighting (attack plans, core-move,
## future hover). Mounted before the overlays so they can bind to it in _ready.
func _mount_highlight_controller() -> void:
	highlight_controller = HighlightController.new()
	highlight_controller.battle_system = battle_system
	highlight_controller.input_ctl = input_ctl
	highlight_controller.allocation_system = allocation_system
	highlight_controller.graph = graph
	highlight_controller.player = player
	graph.add_child(highlight_controller)


func _mount_node_highlight() -> void:
	node_highlight = NodeHighlightOverlay.new()
	node_highlight.highlight_controller = highlight_controller
	node_highlight.graph = graph
	graph.add_child(node_highlight)


func _mount_edge_highlight() -> void:
	# Mounted BEFORE the node-ring overlay so its edge highlights paint below
	# the status rings (later siblings draw on top in Node2D z-order).
	edge_highlight = EdgeHighlightOverlay.new()
	edge_highlight.highlight_controller = highlight_controller
	edge_highlight.graph = graph
	graph.add_child(edge_highlight)


func _mount_attack_vfx() -> void:
	attack_vfx = AttackVFX.new()
	graph.add_child(attack_vfx)


func _mount_allocation_vfx() -> void:
	allocation_vfx = AllocationVFX.new()
	graph.add_child(allocation_vfx)
	allocation_vfx.bind(allocation_system, battle_system)


func _mount_melee_preview() -> void:
	melee_preview = MeleePreview.new()
	melee_preview.battle_system = battle_system
	graph.add_child(melee_preview)


func _mount_floating_number_layer() -> void:
	floating_number_layer = FloatingNumberLayer.new()
	floating_number_layer.vision_system = vision_system
	graph.add_child(floating_number_layer)
