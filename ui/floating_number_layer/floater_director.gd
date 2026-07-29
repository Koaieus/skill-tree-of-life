@tool
class_name FloaterDirector
extends Node2D

## Translates domain facts on the [Events] bus into [FloaterRequest]s and hands
## them to its [FloatingNumberLayer] renderer. The ONLY thing that knows both
## domain meaning AND the floater-style API — domain objects know neither, the
## renderer knows only the latter.
##
## Lives under Graph/ (shares graph world coords); the renderer is its child and
## an implementation detail. Composition: see floater_director.tscn.

## The renderer this director drives (its own child, wired in the scene).
@export var renderer: FloaterToasterManager
## Injected by the composing scene. When set, a floater anchored at a SkillNode
## the player can't see is suppressed (fog). Null → no gating (headless tests /
## fog-less dev sandboxes). This "should it show" policy is the director's, so
## the renderer stays free of any vision dependency.
@export var vision_system: VisionSystem = null

## #91/#108 — when set, entity-level toasts (wound/heal, XP gain) for THIS
## entity render at [member player_anchor] (the Hero Sigil Card's FloatAnchor)
## instead of the world-space core. A plain Node2D works unmodified as a
## [FloaterRequest.target]: the anchor lives under the HUD's CanvasLayer while
## the toaster is world-space, and [method FloaterToaster._on_target_moved]
## maps between the two canvases — copying `global_position` across is NOT
## valid and was a real placement bug. AI entities have no HUD card, so they
## keep rising from their core.
##
## Stat-modifier-gain floaters are the deliberate exception (#306): the modifier
## pulse (`AllocationVFX._launch_modifier_pulse`) already flies node → core in
## world space, and [GainedModifierToast] now owns "you just got these" at the
## sigil. Redirecting the pulse's landing floater there too just teleported it
## across canvases (rendering behind the opaque Hero Sigil Card, since the
## world layer draws under the HUD's CanvasLayer) on top of being visually
## redundant. So [method _on_stat_modifier_changed] always targets the core,
## player or not — see [method _emit_at_entity]'s `route_to_player_anchor` arg.
@export var player: Entity = null
@export var player_anchor: Node2D = null

const FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")


func _ready() -> void:
	Events.skill_node_damaged.connect(_on_skill_node_damaged)
	Events.skill_node_healed.connect(_on_skill_node_healed)
	Events.entity_wounded.connect(_on_entity_wounded)
	Events.entity_healed.connect(_on_entity_healed)
	Events.entity_xp_gained.connect(_on_entity_xp_gained)
	Events.stat_modifier_changed.connect(_on_stat_modifier_changed)


# --- Domain intake → render request -----------------------------------------

func _on_skill_node_damaged(node: SkillNode, amount: float, _source: Variant) -> void:
	if node == null or amount <= 0.0 or not _node_visible(node):
		return
	_emit(node, "%d" % int(round(amount)), FloaterStyles.damage())


func _on_skill_node_healed(node: SkillNode, amount: float, _source: Variant) -> void:
	if node == null or amount <= 0.0 or not _node_visible(node):
		return
	_emit(node, "+%d" % int(round(amount)), FloaterStyles.node_heal())


func _on_entity_wounded(entity: Entity, amount: int) -> void:
	_spawn_at_core(entity, "+%d WOUNDS" % amount, FloaterStyles.entity_wound())


func _on_entity_healed(entity: Entity, amount: int) -> void:
	_spawn_at_core(entity, "-%d WOUNDS" % amount, FloaterStyles.entity_heal())
	_spawn_at_core(entity, "+%d SP" % amount, FloaterStyles.entity_heal())


## XP gained — kill rewards and the per-turn income alike. Routed like any other
## entity-level fact: the player's lands on the Hero Sigil Card, an AI's rises
## from its core (and is fog-gated there).
##
## No hit flash: XP is a reward, not something happening *to* the core, and the
## per-turn income would strobe every core on the board once a turn.
func _on_entity_xp_gained(entity: Entity, amount: float) -> void:
	if amount <= 0.0:
		return
	_emit_at_entity(entity, "+%d XP" % int(round(amount)), FloaterStyles.xp_gain())


## #70/#79 — a stat modifier became visible on an entity. Render its op-aware
## contribution (e.g. "+10 Strength") at the core, styled by binding + gain/loss.
## Always the world-space core, even for the player (#306) — see the
## `player_anchor` docstring's "deliberate exception".
func _on_stat_modifier_changed(
		entity: Entity, modifier: StatModifier, binding: ModifierBinding.Kind, added: bool) -> void:
	if entity == null or modifier == null or entity.core_location == null:
		return
	var def := StatRegistry.get_def(modifier.stat_id)
	var text := modifier.format()
	var tint: Color = def.tint_color if def != null else Color.WHITE
	_emit_at_entity(entity, text, FloaterStyles.for_modifier(tint, binding, added), false)


# --- Helpers ----------------------------------------------------------------

func _emit(target: Node2D, text: String, style: FloaterStyle) -> void:
	if renderer == null or text.is_empty():
		return
	var req := FloaterRequest.new()
	req.target = target
	req.text = text
	req.style = style
	renderer.spawn(req)


## Flash the core itself so the number isn't the only signal — a wound/heal feels
## like an event happening to the core, not just a number popping up nearby —
## then route the actual toast to [method _resolve_target] (Hero Sigil Card
## anchor for the bound player, core for everyone else).
func _spawn_at_core(entity: Entity, text: String, style: FloaterStyle) -> void:
	if _emit_at_entity(entity, text, style):
		entity.core_location.play_hit_flash()


## Route one entity-level fact to wherever that entity's toasts belong: the Hero
## Sigil Card anchor for the bound player, its world-space core for everyone
## else — where the fog gate also applies (a toast on a core you can't see would
## leak the AI's position). [param route_to_player_anchor] lets a caller opt out
## of the sigil redirect even for the player (stat-modifier gains, #306 — see
## the `player_anchor` docstring). Returns whether anything was actually shown,
## so a caller can keep an accompanying effect in step with it.
func _emit_at_entity(
		entity: Entity, text: String, style: FloaterStyle,
		route_to_player_anchor: bool = true) -> bool:
	if entity == null or entity.core_location == null:
		return false
	var core := entity.core_location
	var target := _resolve_target(entity, core, route_to_player_anchor)
	if target == core and not _node_visible(core):
		return false
	_emit(target, text, style)
	return true


func _resolve_target(entity: Entity, core: Node2D, route_to_player_anchor: bool) -> Node2D:
	if route_to_player_anchor and entity == player and is_instance_valid(player_anchor):
		return player_anchor
	return core


func _node_visible(node: SkillNode) -> bool:
	if vision_system == null:
		return true
	return vision_system.is_visible(node)
