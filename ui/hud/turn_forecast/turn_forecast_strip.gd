class_name TurnForecastStrip
extends Control

## Turn-forecast strip beside the [InitiativeBar] (#910, hub #768): the next
## few actors as entity sigils, in [method TurnManager.forecast] order, with
## the seat's own entity highlighted and a caption counting how many act
## before it. Mounted in `hud_root.tscn`; [HudRoot] binds the systems once
## ([method bind]) and re-points the player on every hot-seat handover
## ([method set_player], #459).
##
## [b]Sensor-gated[/b]: a sigil is drawn iff some node the entity owns is
## visible or sensed by this machine's eyes ([method VisionSystem.is_visible]
## / [method VisionSystem.is_sensed]). Unknown entities are omitted — no `?`
## slot — and the caption hedges to "≥ N ahead" when anything before the
## player's first slot was omitted. The seat's own entity is never gated: its
## own territory is by definition in view.
##
## [b]Coalesced[/b]: `forecast_changed` fires once per pool tick per entity
## inside `TurnManager._tick_until_ready`'s synchronous loop, so every signal
## routes through one [DeferredOnce] and the strip rebuilds at most once per
## frame. It never polls in `_process`.

## Sigils shown at rest / while hovered (owner values, 2026-09-16).
@export var rest_count: int = 3
@export var hover_count: int = 8
## Sigil square, px.
@export var sigil_size: float = 24.0

## Hover-expand state. Public so a test (or a controller-driven focus) can
## drive it without synthesising mouse events.
var expanded: bool = false:
	set(v):
		if expanded == v:
			return
		expanded = v
		_rebuild.request()

## Number of completed rebuilds — the coalescing contract's observable.
var rebuild_count: int = 0

@onready var _slots: HBoxContainer = %Slots
@onready var _caption: Label = %Caption

var _turn_manager: TurnManager
var _vision_system: VisionSystem
var _graph: Graph
var _player: Entity
var _slot_entities: Array[Entity] = []
var _systems := SubBag.new()
var _rebuild := DeferredOnce.new(_rebuild_now)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: expanded = true)
	mouse_exited.connect(func() -> void: expanded = false)
	# A bind() that arrived before the tree did was dropped by _rebuild_now's
	# not-ready guard; paint it now.
	if _turn_manager != null:
		_rebuild.request()


## System-lifetime half. Re-callable: releases the previous scope first.
## [param graph] is what the sensor gate walks to find an entity's nodes.
func bind(turn_manager: TurnManager, vision_system: VisionSystem, graph: Graph) -> void:
	_systems.clear()
	_turn_manager = turn_manager
	_vision_system = vision_system
	_graph = graph
	if _turn_manager != null:
		_systems.on(_turn_manager.forecast_changed, _rebuild.request)
	if _vision_system != null:
		_systems.on(_vision_system.visibility_changed, _rebuild.request)
	_rebuild.request()


## Per-seat half: whose sigil is highlighted and whose slot the caption counts
## up to. Null is "nobody" (level teardown).
func set_player(player: Entity) -> void:
	_player = player
	_rebuild.request()


## Entities behind the drawn sigils, in slot order (an entity may repeat).
func get_slot_entities() -> Array[Entity]:
	return _slot_entities.duplicate()


func is_slot_highlighted(index: int) -> bool:
	if index < 0 or index >= _slot_entities.size():
		return false
	return _slot_entities[index] == _player


func get_caption() -> String:
	return _caption.text if _caption != null else ""


func _rebuild_now() -> void:
	if not is_inside_tree() or _slots == null:
		return
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	_slot_entities.clear()
	rebuild_count += 1
	if _turn_manager == null:
		_caption.text = ""
		return

	var n: int = hover_count if expanded else rest_count
	var ahead: int = 0
	var hedged: bool = false
	var seen_player: bool = false
	for e in _turn_manager.forecast(n):
		if e == null or not is_instance_valid(e):
			continue
		if not _is_sensed(e):
			if not seen_player:
				hedged = true
			continue
		if e == _player:
			seen_player = true
		elif not seen_player:
			ahead += 1
		_slot_entities.append(e)
		_slots.add_child(_make_slot(e, e == _player))
	# A player never seen in the window: every drawn actor is ahead, and so
	# is an unknown number past the window — hedge.
	if not seen_player and _player != null:
		hedged = true
	_caption.text = ("≥ %d ahead" if hedged else "%d ahead") % ahead


## The sensor gate: any owned node visible or sensed. No vision system (a
## hand-built HUD fixture) means no fog, so everything is sensed.
func _is_sensed(entity: Entity) -> bool:
	if entity == _player or _vision_system == null or _graph == null:
		return true
	for node in _graph.get_skill_nodes():
		if node.owned_by == entity \
				and (_vision_system.is_visible(node) or _vision_system.is_sensed(node)):
			return true
	return false


## One sigil: the class [Sigil] in the entity's colour ([SigilGlyph], the same
## glyph [HeroSigilCard] draws), or a plain colour dot when the class has no
## sigil authored. The seat's own entity gets a lit border in its colour —
## a named tier via [Emissive], never a hand-picked float.
func _make_slot(entity: Entity, highlighted: bool) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(sigil_size, sigil_size)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.tooltip_text = entity.display_name
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(4)
	if highlighted:
		style.set_border_width_all(2)
		style.border_color = Emissive.tint(entity.color, Emissive.VALUE)
	slot.add_theme_stylebox_override(&"panel", style)

	var sigil: Sigil = entity.core_class.sigil if entity.core_class != null else null
	if sigil != null:
		var glyph := SigilGlyph.new()
		glyph.sigil = sigil
		glyph.entity_tint = entity.color
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(glyph)
	else:
		var dot := ColorRect.new()
		dot.color = entity.color
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pad := MarginContainer.new()
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_theme_constant_override(&"margin_left", 6)
		pad.add_theme_constant_override(&"margin_right", 6)
		pad.add_theme_constant_override(&"margin_top", 6)
		pad.add_theme_constant_override(&"margin_bottom", 6)
		pad.add_child(dot)
		slot.add_child(pad)
	return slot
