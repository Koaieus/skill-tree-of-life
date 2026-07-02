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

const FloaterStyles := preload("res://ui/floating_number_layer/floater_styles.gd")


func _ready() -> void:
	Events.skill_node_damaged.connect(_on_skill_node_damaged)
	Events.skill_node_healed.connect(_on_skill_node_healed)
	Events.entity_wounded.connect(_on_entity_wounded)
	Events.entity_healed.connect(_on_entity_healed)
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


## #70/#79 — a stat modifier became visible on an entity. Render its op-aware
## contribution (e.g. "+10 Strength") at the core, styled by binding + gain/loss.
func _on_stat_modifier_changed(
		entity: Entity, modifier: StatModifier, binding: ModifierBinding.Kind, added: bool) -> void:
	if entity == null or modifier == null or entity.core_location == null:
		return
	var core := entity.core_location
	if not _node_visible(core):
		return
	var def := StatRegistry.get_def(modifier.stat_id)
	var label: String = def.display_name if def != null else String(modifier.stat_id)
	var text := "%s %s" % [modifier.contribution_text(), label]
	var tint: Color = def.tint_color if def != null else Color.WHITE
	_emit(core, text, FloaterStyles.for_modifier(tint, binding, added))


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
## like an event happening to the core, not just a number popping up nearby.
func _spawn_at_core(entity: Entity, text: String, style: FloaterStyle) -> void:
	if entity == null or entity.core_location == null:
		return
	var core := entity.core_location
	if not _node_visible(core):
		return
	core.play_hit_flash()
	_emit(core, text, style)


func _node_visible(node: SkillNode) -> bool:
	if vision_system == null:
		return true
	return vision_system.is_visible(node)
