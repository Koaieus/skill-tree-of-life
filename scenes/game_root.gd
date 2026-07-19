class_name GameRoot
extends Node2D

## Composition root for a level: holds the live references that HudRoot (and
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

## Intent flags — let a subclass / inherited scene run a *neutered* GameRoot
## (e.g. a live showcase in an editor tab) without the parts a self-driven demo
## doesn't want. The owner toggles its own children here; nobody reaches in from
## outside. Defaults preserve full-game behaviour, so real levels are untouched.
@export_group("Showcase / embed")
## When false, `_ready` skips the opening `start_turn` — the turn loop never
## kicks, so a showcase can drive its own beat loop (and set `current_entity`
## directly for killer attribution) without TurnManager/AI taking over.
@export var auto_start_turn: bool = true
## When false, `_ready` skips `HudRoot.compose` and hides the UI layer.
@export var show_ui: bool = true
## When false, the fog overlay is hidden (a self-driven demo wants every node
## visible regardless of owned-subgraph vision).
@export var enable_fog: bool = true

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
@onready var highlight_controller: HighlightController = %HighlightController

@onready var floater_director: FloaterDirector = %FloaterDirector

# UI
@onready var camera: Camera2D = %GraphCamera
@onready var hud_root: HudRoot = %HudRoot

@onready var node_highlight: NodeHighlightOverlay = %NodeHighlightOverlay
@onready var edge_highlight: EdgeHighlightOverlay = %EdgeHighlightOverlay
@onready var attack_vfx: AttackVFX = %AttackVFX
@onready var allocation_vfx: AllocationVFX = %AllocationVFX
@onready var melee_preview: MeleePreview = %MeleePreview


func _ready() -> void:
	# Entity death (#18): AllocationSystem strips the corpse's nodes off the same
	# bus signal; GameRoot owns the player-vs-NPC consequence (game-over / despawn).
	Events.entity_died.connect(_on_entity_died)

	# Scene-authored ownership (dev_sandbox-style) must claim SP before
	# _setup_level runs — procgen spawning goes through force_allocate which
	# claims itself, but hand-authored owned_by= assignments skip that path.
	allocation_system.register_scene_authored_ownership()
	# _setup_level runs BEFORE hud_root.compose because compose reads
	# `player.stat_board` immediately — procgen sandboxes that spawn the
	# player here need the entity in place first. `await` is harmless on
	# synchronous overrides; procgen sandboxes that drive a loading bar
	# return a coroutine.
	await _setup_level()
	# Invariant: every Entity must have an EntityController child so the
	# turn loop never stalls on an uncontrolled actor. Hand-authored
	# scenes (dev_sandbox, first_level_sandbox) historically forgot to
	# attach AIController to enemies; this defaulter is the catch-all
	# that keeps every sandbox playable without per-scene wiring.
	_ensure_controllers()
	bind_player(player)
	if not enable_fog:
		if has_node("%FogOverlay"):
			(get_node("%FogOverlay") as CanvasItem).visible = false
		# Floaters must not query the (dormant, non-@tool) VisionSystem for
		# per-node visibility in a no-fog showcase — calling a method on a
		# non-@tool node from the editor is the boundary-error class. Null it so
		# every floater shows (mirrors SandboxWorld's no-player wiring).
		if floater_director != null:
			floater_director.vision_system = null
	if show_ui:
		if hud_root != null:
			hud_root.compose(self)
		_wire_hud_floater_anchor()
	else:
		$UI.visible = false

	if auto_start_turn and player != null and turn_manager != null:
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
## the level reading as "still playable". Emits the [signal Events.game_over] bus
## signal; HudRoot listens and toggles its pre-composed overlay visible.
func _show_game_over() -> void:
	Events.game_over.emit()


## Wire a (possibly late-resolved) human player into the *player-interaction*
## layer — faction, highlight fallback owner, input controller, vision viewer.
## Null-safe + idempotent: GameRoot calls it once at the tail of `_ready` (after
## `_setup_level` has had its chance to set `player`), and a level that resolves
## its player asynchronously — or swaps it — can call it again.
##
## A self-driven showcase passes `null` (no human player): every dependant is
## left untouched, which is exactly what keeps these non-`@tool` systems dormant
## when a neutered GameRoot runs live in an editor tab. Don't move per-player
## wiring back out into `_ready` — routing it through here is what makes the
## no-player path clean.
func bind_player(p: Entity) -> void:
	player = p
	if player == null:
		return
	player.faction = &"player"
	highlight_controller.player = player
	input_ctl.player = player
	if vision_system != null:
		vision_system.viewers = [player] as Array[Entity]


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
	var ent := preload("res://entity/entity.tscn").instantiate() as Entity
	ent.name = ent_name
	ent.display_name = ent_name
	ent.color = color
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


## #91/#108 — routes the player's entity-level toasts (wound/heal, stat
## modifier gain) to the Hero Sigil Card's FloatAnchor instead of the
## world-space core. No-op if the HUD isn't composed (show_ui == false) or
## the player hasn't resolved yet.
func _wire_hud_floater_anchor() -> void:
	if floater_director == null or hud_root == null or player == null:
		return
	if hud_root.hero_sigil_card == null:
		return
	floater_director.player = player
	floater_director.player_anchor = hud_root.hero_sigil_card.float_anchor


func _focus_camera_on_player() -> void:
	if camera == null or player == null:
		return
	var target: Vector2 = player.core_location.global_position if player.core_location != null else player.position
	camera.position = target
