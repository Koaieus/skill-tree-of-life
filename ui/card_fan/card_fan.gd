@tool
class_name CardFan
extends Control

## A growing fan of fixed-size [TempUpgradeButton] cards around a centre
## [code]%Hub[/code] button. Pure view: entries in, signals out.
##
## The fan's origin is the hub's centre. Slot [code]i[/code] depends only on
## [code]i[/code] and the knobs ([method slot_position]): from 12 o'clock,
## clockwise, [member slot_step_deg] apart, and past [member max_arc_deg] the
## next slot starts a ring farther out. So binding fewer entries draws fewer
## cards, never moves the ones drawn, and never shows how many slots exist.
## Generic over the entries' meaning: the caller decides what a pick does.

## Left-click on a card.
signal picked(scene: PackedScene)
## The pointer entered a card, or left one ([code]null[/code]).
signal hovered(scene: PackedScene)
## Right-click on the hub, or [code]ui_cancel[/code] while it shows.
signal dismissed
## The centre button was pressed.
signal hub_pressed

## Distance from the hub's centre to a first-ring card's centre. Tentative.
@export_range(32.0, 400.0, 1.0) var ring_radius_px: float = 110.0:
	set(v):
		ring_radius_px = v
		_relayout()
## Angle between neighbouring slots on one ring. Tentative.
@export_range(5.0, 180.0, 0.5) var slot_step_deg: float = 34.0:
	set(v):
		slot_step_deg = v
		_relayout()
## Widest arc one ring spans before the next slot starts a farther ring. Tentative.
@export_range(0.0, 360.0, 1.0) var max_arc_deg: float = 200.0:
	set(v):
		max_arc_deg = v
		_relayout()
## How much farther out each further ring sits. Tentative.
@export_range(0.0, 400.0, 1.0) var ring_gap_px: float = 8.0:
	set(v):
		ring_gap_px = v
		_relayout()
## Editor-only preview: entries bound while the scene is open in the editor,
## so the knobs above show their effect. Ignored at runtime.
@export var preview_entries: Array[PackedScene] = []:
	set(v):
		preview_entries = v
		if Engine.is_editor_hint() and is_node_ready():
			bind(preview_entries, SkillNodeAddon.temp_costs_of, [])

const _CARD := preload("res://ui/hud/command_tray/bodies/temp_upgrade_button.tscn")

@onready var _cards: Control = %Cards
@onready var _hub: Button = %Hub

var _entries: Array[PackedScene] = []


func _ready() -> void:
	_hub.pressed.connect(hub_pressed.emit)
	_hub.gui_input.connect(_on_child_gui_input)
	if Engine.is_editor_hint() and not preview_entries.is_empty():
		bind(preview_entries, SkillNodeAddon.temp_costs_of, [])
	_relayout()


## Where slot [param i]'s card centre sits, relative to the hub's centre:
## [param step] degrees apart clockwise from 12 o'clock, a ring holding every
## slot within [param max_arc], each further ring [param ring_gap] farther out.
static func slot_position(i: int, ring_radius: float, step: float, max_arc: float, ring_gap: float) -> Vector2:
	var per_ring := floori(max_arc / step) + 1 if step > 0.0 else 1
	per_ring = maxi(per_ring, 1)
	@warning_ignore("integer_division")  # intended truncation: ring index
	var ring := i / per_ring
	var angle := deg_to_rad((i % per_ring) * step) - PI / 2.0
	return Vector2(cos(angle), sin(angle)) * (ring_radius + ring * ring_gap)


## One card per entry, in [param entries]' order. [param costs_of] maps an
## entry to the price its card prints ([code]Dictionary[StringName, int][/code]);
## an entry in [param lit] draws armed (already placed).
func bind(entries: Array[PackedScene], costs_of: Callable, lit: Array[PackedScene]) -> void:
	_entries = entries.duplicate()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for scene in _entries:
		var card := _CARD.instantiate() as TempUpgradeButton
		var tmp := scene.instantiate() as SkillNodeAddon
		card.label_text = tmp.get_tooltip_title()
		tmp.free()
		card.icon_texture = SkillNodeAddon.icon_of(scene)
		card.accent = SkillNodeAddon.tint_of(scene)
		card.costs = costs_of.call(scene)
		card.armed = lit.has(scene)
		card.pressed.connect(picked.emit.bind(scene))
		card.mouse_entered.connect(hovered.emit.bind(scene))
		card.mouse_exited.connect(hovered.emit.bind(null))
		card.gui_input.connect(_on_child_gui_input)
		_cards.add_child(card)
	_relayout()


## The bound cards, in entry order.
func cards() -> Array[TempUpgradeButton]:
	var out: Array[TempUpgradeButton] = []
	if _cards == null:
		return out
	for child in _cards.get_children():
		out.append(child as TempUpgradeButton)
	return out


## Every card takes the largest card's minimum size, centred on its slot; the
## hub centres on the origin.
func _relayout() -> void:
	if not is_node_ready():
		return
	var slot_size := Vector2.ZERO
	for card in cards():
		slot_size = slot_size.max(card.get_combined_minimum_size())
	var i := 0
	for card in cards():
		card.size = slot_size
		card.position = slot_position(i, ring_radius_px, slot_step_deg, max_arc_deg, ring_gap_px) - slot_size * 0.5
		i += 1
	_hub.size = _hub.get_combined_minimum_size()
	_hub.position = -_hub.size * 0.5


func _on_child_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		dismissed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and not _entries.is_empty() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		dismissed.emit()
