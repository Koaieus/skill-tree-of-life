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

## Removable blocker sizes (#300). Tier = size + 1 (SMALL → 1, MEDIUM → 2,
## LARGE → 3); see [method spawn_blocker]. Procgen blocker placements carry
## this enum's int value as the per-node `size` marker.
enum BlockerSize { SMALL, MEDIUM, LARGE }

const _BLOCKER_SCENE := preload("res://entity/blocker/blocker_entity.tscn")
const _BLOCKER_BOARDS: Dictionary = {
	BlockerSize.SMALL: preload("res://entity/blocker/blocker_small_board.tres"),
	BlockerSize.MEDIUM: preload("res://entity/blocker/blocker_medium_board.tres"),
	BlockerSize.LARGE: preload("res://entity/blocker/blocker_large_board.tres"),
}
const _BLOCKER_SPELLBOOKS: Dictionary = {
	BlockerSize.SMALL: preload("res://entity/blocker/blocker_spellbook_small.tres"),
	BlockerSize.MEDIUM: preload("res://entity/blocker/blocker_spellbook_medium.tres"),
	BlockerSize.LARGE: preload("res://entity/blocker/blocker_spellbook_large.tres"),
}

## Dev shortcut (#244): `F` flips FogOverlay.intensity between fully opaque
## (ship default, 1.0) and the dimmer "almost black" (0.88) that lets a dev see
## enemy positions through unsensed fog.
const _FOG_DEBUG_KEY: int = KEY_F
const _FOG_INTENSITY_SHIP: float = 1.0
const _FOG_INTENSITY_DEV: float = 0.88

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

## Grown around the graph's SkillNode AABB to get the fog/aura bound, and
## passed to the camera as its zoom==1.0 pan-margin baseline (GraphCamera
## scales it by 1/zoom past that) — breathing room so a node sitting exactly
## on the edge doesn't touch the viewport border, tweakable per level.
@export_range(0, 2000, 1.0, "or_greater") var graph_bounds_margin: float = 900.0

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
@onready var fog_overlay: FogOverlay = %FogOverlay
@onready var aura_overlay: AuraOverlay = %AuraOverlay

# UI
@onready var camera: GraphCamera = %GraphCamera
@onready var hud_root: HudRoot = %HudRoot

@onready var node_highlight: NodeHighlightOverlay = %NodeHighlightOverlay
@onready var edge_highlight: EdgeHighlightOverlay = %EdgeHighlightOverlay
@onready var attack_vfx: AttackVFX = %AttackVFX
@onready var allocation_vfx: AllocationVFX = %AllocationVFX
@onready var melee_preview: MeleePreview = %MeleePreview
@onready var presentation_player: PresentationPlayer = %PresentationPlayer


func _ready() -> void:
	# Presentation clock v2 (#489): static state outlives a scene change, so
	# this must be paired with the `_exit_tree` clear below or a level reload
	# leaves RevealRecorder.player dangling at a freed node.
	RevealRecorder.player = presentation_player

	# Entity death (#18): AllocationSystem strips the corpse's nodes off the same
	# bus signal; GameRoot owns the player-vs-NPC consequence (game-over / despawn).
	Events.entity_died.connect(_on_entity_died)
	# Presentation clock (#479): the VISUAL consequence (despawn / game-over)
	# waits for the killing blow's own reveal — see `_on_entity_death_shown`.
	Events.entity_death_shown.connect(_on_entity_death_shown)

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
	_apply_graph_bounds()
	# Invariant: every Entity must have an EntityController child so the
	# turn loop never stalls on an uncontrolled actor. Hand-authored
	# scenes (dev_sandbox, first_level_sandbox) historically forgot to
	# attach AIController to enemies; this defaulter is the catch-all
	# that keeps every sandbox playable without per-scene wiring.
	_ensure_controllers()
	bind_player(player)
	if not enable_fog:
		if fog_overlay != null:
			fog_overlay.visible = false
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
		_wire_gained_modifier_toast()
		# Container layout (HeroSigilCard's MarginContainer/VBoxContainer chain)
		# is resolved via a queued `sort_children`, which hasn't flushed yet this
		# far into the same synchronous _ready — Controls still report their
		# pre-layout (0,0)-ish rects. `start_turn` below fires synchronously and
		# can trigger a same-frame XP gain toast at the Hero Sigil Card's
		# FloatAnchor; reading its position before layout settles popped that
		# toast at the viewport's top-left corner instead of the card. One frame
		# is enough for the deferred sort to flush.
		await get_tree().process_frame
	else:
		$UI.visible = false

	if auto_start_turn and player != null and turn_manager != null:
		# Skip the initial tick race: fill the player's clock so they act first.
		# (start_turn clears the ready-group membership this would otherwise set.)
		if player.stat_board != null and player.stat_board.initiative != null:
			player.stat_board.initiative.restore_to_full()
		turn_manager.start_turn(player)
	_focus_camera_on_player()


## Presentation clock v2 (#489): `RevealRecorder`'s static state outlives this
## scene, so it must be cleared here or a level reload leaves
## `RevealRecorder.player` pointing at this (about-to-be-freed) player, and
## any in-flight recording dangling too.
func _exit_tree() -> void:
	if RevealRecorder.player == presentation_player:
		RevealRecorder.player = null
	if RevealRecorder.is_recording:
		RevealRecorder.end()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode != _FOG_DEBUG_KEY:
		return
	if fog_overlay == null:
		return
	fog_overlay.intensity = _FOG_INTENSITY_DEV if fog_overlay.intensity == _FOG_INTENSITY_SHIP else _FOG_INTENSITY_SHIP
	get_viewport().set_input_as_handled()


## Entity death consequence (#18). Node-stripping is AllocationSystem's job (it
## also listens to `entity_died`); here we handle the turn-loop-critical half of
## what's left SYNCHRONOUSLY — an NPC corpse must not hold/receive a turn — and
## defer the VISUAL half (despawn / game-over) to `_on_entity_death_shown`
## (#479), so the corpse stays on screen through its own death VFX instead of
## vanishing at raw model-mutation time.
##
## `entity.health_presentation_held` is true iff the killing hit took a
## presentation hold before depleting `health` (every attack-caused death does,
## see `Entity.release_health_presentation`) — if nothing is holding, there's
## no reveal to wait for (upkeep, an effect, a test calling `die()` directly),
## so reveal immediately, same as before #479's gate.
func _on_entity_died(entity: Entity) -> void:
	if entity == null:
		return
	if entity != player:
		_pull_npc_from_turn_loop(entity)
	if not entity.health_presentation_held:
		_reveal_entity_death(entity)


## Pull a dead NPC out of the turn-loop groups SYNCHRONOUSLY so TurnManager's
## tick / `_tick_until_ready` skip it this frame — `queue_free` leaves the node
## valid (and group-resident) until frame end, or later still under #479's
## reveal gate, so the group removal can't wait for either. Defensive: if the
## corpse somehow held the turn, clear `current_entity` so the loop isn't
## stalled on an actor that's about to disappear.
func _pull_npc_from_turn_loop(entity: Entity) -> void:
	entity.remove_from_group(Entity.GROUP)
	entity.remove_from_group(Entity.READY_GROUP)
	if turn_manager != null and turn_manager.current_entity == entity:
		turn_manager.current_entity = null


## Presentation clock (#479): the killing blow's own reveal has landed (or, per
## `_on_entity_died`, nothing was ever going to reveal one) — do the actual
## despawn / game-over now.
func _on_entity_death_shown(entity: Entity) -> void:
	_reveal_entity_death(entity)


## Free order is safe: AllocationSystem's death handler deallocates the corpse's
## nodes SYNCHRONOUSLY (off `entity_died`, before either call path here can
## run), so freeing the entity itself — now or after the reveal gate — can't
## orphan them.
func _reveal_entity_death(entity: Entity) -> void:
	if not is_instance_valid(entity):
		return
	if entity == player:
		_show_game_over()
	else:
		entity.queue_free()


## Game-over placeholder (#18). The full screen lives in the Metagame milestone;
## for now a dim overlay + label is enough to make player-death visible and stop
## the level reading as "still playable". Emits the [signal Events.game_over] bus
## signal; HudRoot listens and toggles its pre-composed overlay visible.
func _show_game_over() -> void:
	Events.game_over.emit()


## Wire a (possibly late-resolved) human player into the *player-interaction*
## layer — highlight fallback owner, input controller, vision viewer. Faction
## and controller kind are decided elsewhere (#475: [method apply_roster], or
## authored directly on a hand-authored scene's node) — this only wires the
## camera/HUD's notion of "who am I looking through".
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
	highlight_controller.player = player
	input_ctl.player = player
	if vision_system != null:
		vision_system.viewers = [player] as Array[Entity]


## Attaches a default [EntityController] child to any [Entity] in the level
## that doesn't already have one: [PlayerController] where [member
## Entity.is_human_controlled] is set, [AIController] otherwise. No-op if the
## scene/code already wired a controller — explicit composition always wins.
##
## Reads [member Entity.is_human_controlled] rather than comparing identity
## against [member player] — that authored-per-entity flag is what
## [method apply_roster] sets from a [Participant]'s kind, and it's also what
## a hand-authored scene (dev_sandbox) sets directly on its `%Player` node.
## #475: this is the seam that stops assuming "the player" is singular.
func _ensure_controllers() -> void:
	for node in get_tree().get_nodes_in_group("entities"):
		var ent := node as Entity
		if ent == null:
			continue
		if _find_controller(ent) != null:
			continue
		var ctrl: EntityController
		if ent.is_human_controlled:
			ctrl = PlayerController.new()
			ctrl.name = "PlayerController"
		else:
			ctrl = AIController.new()
			ctrl.name = "AIController"
		ent.add_child(ctrl)


## Applies each roster participant's authored camp + control-kind onto its
## already-spawned entity — the roster-driven replacement for deciding
## faction or controller from "is this entity named player" (#475).
## [param entities_by_participant_id] maps [member Participant.id] to the
## [Entity] spawned for it; participants with no matching entry, or whose
## [member Participant.camp] is unset, are skipped. Static + side-effect-only
## on the entities: no dependency on a live GameRoot, so it's testable
## against a roster built in isolation, not against lobby UI.
static func apply_roster(entities_by_participant_id: Dictionary, roster: ParticipantRoster) -> void:
	for participant in roster.all():
		var ent: Entity = entities_by_participant_id.get(participant.id)
		if ent == null or participant.camp == null:
			continue
		ent.faction = participant.camp
		ent.is_human_controlled = participant.kind != Participant.Kind.AI


static func _find_controller(ent: Entity) -> EntityController:
	for child in ent.get_children():
		if child is EntityController:
			return child as EntityController
	return null


## Subclass hook. Default = pick up an existing `%Player` node from the scene
## (dev_sandbox shape). Procgen sandboxes override to run generation + spawn
## entities, then assign `self.player`.
func _setup_level() -> void:
	if false: await get_tree().process_frame # include fake `await` to make godot see this as a coroutine
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


## Spawn a removable blocker entity (#300) owning [param core_location]. A
## blocker is a plain [Entity] — no controller, no [CoreClass] — whose tiered
## board ([param size] → CON/armor/health, no initiative) and the size's
## spellbook are authored under `entity/blocker/`. Parents under
## `graph.entities_container` and force-allocates the core, exactly like
## [method spawn_entity] (procgen setup, not a gameplay action). Returns the
## entity, with [member Entity.entity_tier] set to size + 1 (1/2/3).
func spawn_blocker(size: BlockerSize, core_location: SkillNode) -> Entity:
	var ent := _BLOCKER_SCENE.instantiate() as Entity
	ent.name = "Blocker_%s" % BlockerSize.keys()[size].to_lower()
	ent.display_name = ent.name
	ent.entity_tier = int(size) + 1
	ent.stat_board = _BLOCKER_BOARDS[size] as EntityStatBoard
	ent.spellbook = _BLOCKER_SPELLBOOKS[size] as SpellBook
	graph.entities_container.add_child(ent)
	if core_location != null:
		allocation_system.force_allocate(ent, core_location)
		ent.core_location = core_location
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


## #306 — "you just got these": on a voluntary player allocation, slab the
## node's granted modifiers beside the Hero avatar, then absorb them into it.
##
## Its own layer, deliberately NOT the floater queue (different dwell, anchor
## and exit). Mounted in HudRoot rather than under Graph like FloaterDirector,
## so it sits in the HUD canvas and does not scale with camera zoom.
##
## Two gates, neither of which the toast decides for itself:
##   - `entity == player` — this is the HERO avatar's surface; an NPC
##     allocating a node must not toast on it.
##   - `not forced` — mirrors the existing convention for cosmetic gain
##     reactions (see AllocationSystem's `allocated` docstring: #70 floaters
##     and #71 pulses gate the same way), so a level's setup/procgen
##     allocations don't fire a flurry at startup.
func _wire_gained_modifier_toast() -> void:
	if allocation_system == null or hud_root == null or player == null:
		return
	if hud_root.hero_sigil_card == null or hud_root.gained_modifier_toast == null:
		return
	hud_root.gained_modifier_toast.float_anchor = hud_root.hero_sigil_card.float_anchor
	if not allocation_system.allocated.is_connected(_on_node_allocated_for_toast):
		allocation_system.allocated.connect(_on_node_allocated_for_toast)


func _on_node_allocated_for_toast(node: SkillNode, entity: Entity, forced: bool) -> void:
	if forced or entity != player or node == null:
		return
	if hud_root == null or hud_root.gained_modifier_toast == null:
		return
	hud_root.gained_modifier_toast.show_gains(node.modifiers)


## Bounds the camera pan and the fog-of-war / aura paint rects to the graph's
## own footprint — a hand-authored sandbox and a 3000-radius procgen level
## shouldn't share one hardcoded rect. Runs once, after `_setup_level()`
## has populated the graph (nodes don't exist before that — see the camera's
## own `_zoom_by` resync comment for the same ordering gotcha).
##
## The limit rect is exactly the AABB + margin, no bigger — so on a small
## graph (dev_sandbox) it can end up smaller than the viewport at
## [constant GraphCamera.MIN_ZOOM]. Rather than grow the limit rect past the
## graph's actual footprint to cover that, push a matching zoom-out floor onto
## the camera instead: [method Camera2D.limit_*] degenerates once the view
## rect exceeds the limit rect, and stopping the zoom-out there keeps the two
## in agreement without inflating what the fog paints.
func _apply_graph_bounds() -> void:
	if graph == null:
		return
	var raw_bounds := graph.get_node_bounds()
	if raw_bounds.size == Vector2.ZERO:
		return
	var baseline_bounds := raw_bounds.grow(graph_bounds_margin)

	if camera != null:
		if not camera.bounds_changed.is_connected(_on_camera_bounds_changed):
			camera.bounds_changed.connect(_on_camera_bounds_changed)
		# Camera gets the RAW bounds + the margin as a zoom==1.0 baseline, not
		# the pre-grown `baseline_bounds` rect — it re-derives its own pan
		# limit every frame, scaling the margin by 1/zoom
		# (GraphCamera._update_limits), then pushes the result back via
		# `bounds_changed` so fog/aura paint the same zoom-scaled rect instead
		# of a second, independently-computed one (see _on_camera_bounds_changed).
		camera.set_graph_bounds(raw_bounds, graph_bounds_margin)
		var viewport_size := get_viewport().get_visible_rect().size
		var min_zoom_floor: float = maxf(viewport_size.x / baseline_bounds.size.x, viewport_size.y / baseline_bounds.size.y)
		camera.set_min_zoom_floor(min_zoom_floor)
	else:
		# No camera (e.g. an embedded showcase) — nothing will ever fire
		# `bounds_changed`, so fall back to the static zoom==1.0 rect directly.
		_on_camera_bounds_changed(baseline_bounds)


## Mirrors GraphCamera's zoom-scaled pan limit onto the fog/aura overlays so
## all three always agree on how far past the graph edge is visible.
func _on_camera_bounds_changed(bounds: Rect2) -> void:
	if fog_overlay != null:
		fog_overlay.bounds = bounds
	if aura_overlay != null:
		aura_overlay.bounds = bounds


func _focus_camera_on_player() -> void:
	if camera == null or player == null:
		return
	var target: Vector2 = player.core_location.global_position if player.core_location != null else player.position
	camera.position = target
