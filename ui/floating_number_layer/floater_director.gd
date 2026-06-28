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
@export var renderer: FloatingNumberLayer
## Injected by the composing scene. When set, a floater anchored at a SkillNode
## the player can't see is suppressed (fog). Null → no gating (headless tests /
## fog-less dev sandboxes). This "should it show" policy is the director's, so
## the renderer stays free of any vision dependency.
@export var vision_system: VisionSystem = null

const _COLOR_DAMAGE := Color(1.0, 0.85, 0.85, 1.0)
const _COLOR_WOUND  := Color(1.0, 0.55, 0.55, 1.0)
const _COLOR_HEAL   := Color(0.65, 1.0, 0.7, 1.0)
## Gold blended into the stat tint for the CORE-bound modifier floater (#70).
const _COLOR_MYTHIC := Color(1.0, 0.84, 0.3, 1.0)


func _ready() -> void:
	Events.skill_node_damaged.connect(_on_skill_node_damaged)
	Events.entity_wounded.connect(_on_entity_wounded)
	Events.entity_healed.connect(_on_entity_healed)
	Events.stat_modifier_changed.connect(_on_stat_modifier_changed)


# --- Domain intake → render request -----------------------------------------

func _on_skill_node_damaged(node: SkillNode, amount: float, _source: Variant) -> void:
	if node == null or amount <= 0.0 or not _node_visible(node):
		return
	_emit(node, "%d" % int(round(amount)), _basic_style(_COLOR_DAMAGE))


func _on_entity_wounded(entity: Entity, amount: int) -> void:
	_spawn_at_core(entity, "+%d WOUNDS" % amount, _COLOR_WOUND)


func _on_entity_healed(entity: Entity, amount: int) -> void:
	_spawn_at_core(entity, "-%d WOUNDS" % amount, _COLOR_HEAL)
	_spawn_at_core(entity, "+%d SP" % amount, _COLOR_HEAL)


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
	_emit(core, text, _modifier_style(tint, binding, added))


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
func _spawn_at_core(entity: Entity, text: String, color: Color) -> void:
	if entity == null or entity.core_location == null:
		return
	var core := entity.core_location
	if not _node_visible(core):
		return
	core.play_hit_flash()
	_emit(core, text, _basic_style(color))


func _basic_style(color: Color) -> FloaterStyle:
	var s := FloaterStyle.new()
	s.fill_color = color
	return s


## Per-variant modifier styling (#70). Removed → desaturated + drifts down
## ("lost"); CORE-bound add → gold-blended glow, bigger + slower (build-defining);
## NODE add (default) → the stat's plain tint. (#78 will refine this matrix.)
func _modifier_style(tint: Color, binding: ModifierBinding.Kind, added: bool) -> FloaterStyle:
	var s := FloaterStyle.new()
	if not added:
		var grey := (tint.r + tint.g + tint.b) / 3.0
		s.fill_color = tint.lerp(Color(grey, grey, grey, 1.0), 0.6)
		s.float_distance = -55.0  # drift down — "lost", not "gained"
		return s
	if binding == ModifierBinding.Kind.CORE:
		s.fill_color = tint.lerp(_COLOR_MYTHIC, 0.6)
		s.glow = true
		s.font_size = 46
		s.float_time = 3.6
	else:
		s.fill_color = tint
	return s


func _node_visible(node: SkillNode) -> bool:
	if vision_system == null:
		return true
	return vision_system.is_visible(node)
