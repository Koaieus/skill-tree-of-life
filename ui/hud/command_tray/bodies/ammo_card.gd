@tool
class_name AmmoCard
extends PanelContainer
## One tall card of the ranged inventory: an [AmmoType]'s count in this
## volley, a [SendBar] over a [SheafPile] of its stock, `stock +gain`, and its
## name; the effect line is the hover tooltip. Pure view: fed numbers, it asks
## for changes through its signals and never sets its own count.
##
## Grammar: drag / click / scroll the bar = that count (via
## [signal set_requested]); left-click the count label = all, right-click =
## none. The base card also carries the fill toggle ([member has_fill_toggle]).

signal set_requested(type_id: StringName, count: int)
signal all_requested(type_id: StringName)
signal none_requested(type_id: StringName)
signal fill_toggled(on: bool)

## Edge length of the status badge.
@export_range(12, 64) var badge_px: int = 20:
	set(value):
		badge_px = value
		if _status_badge != null:
			_status_badge.size_px = value
## Share of the pile's width the send bar covers; the rest peeks out beside it.
@export_range(0.2, 1.0) var pile_cover: float = 0.66:
	set(value):
		pile_cover = value
		_layout_stack()
## The card's minimum width, px; its minimum height is this × [member aspect].
@export_range(40, 160) var min_width: int = 68:
	set(value):
		min_width = value
		_apply_min_size()
## Height over width — above 1 keeps the card taller than wide.
@export_range(1.0, 3.0) var aspect: float = 1.65:
	set(value):
		aspect = value
		_apply_min_size()
## Shows the fill toggle (the base card's, baked into the body's scene).
@export var has_fill_toggle: bool = false:
	set(value):
		has_fill_toggle = value
		if is_node_ready():
			_fill_toggle.visible = value

var type: AmmoType = null
var stock: int = 0
var gain: int = 0
var count: int = 0
## The most "all" gives: min(bin, what the volley still holds).
var cap: int = 0
var fill: bool = true

@onready var _name_label: Label = %NameLabel
@onready var _status_badge: IdentityBadge = %StatusBadge
@onready var _stock_label: Label = %StockLabel
@onready var _count_label: Label = %CountLabel
@onready var _fill_toggle: Button = %FillToggle
@onready var _stack: Control = %Stack
@onready var _send_bar: SendBar = %SendBar
@onready var _pile: SheafPile = %SheafPile


func _ready() -> void:
	_count_label.gui_input.connect(_on_count_input)
	_send_bar.value_requested.connect(_on_bar_requested)
	_fill_toggle.toggled.connect(_on_fill_toggled)
	_stack.resized.connect(_layout_stack)
	_status_badge.size_px = badge_px
	_fill_toggle.visible = has_fill_toggle
	_apply_min_size()
	_layout_stack()
	_paint()


func setup(p_type: AmmoType) -> void:
	type = p_type
	if is_node_ready():
		_paint()


func set_stock(p_stock: int, p_gain: int) -> void:
	stock = p_stock
	gain = p_gain
	if is_node_ready():
		_paint()


func set_count(p_count: int, p_cap: int) -> void:
	count = p_count
	cap = p_cap
	if is_node_ready():
		_paint()


func set_fill(on: bool) -> void:
	fill = on
	if is_node_ready():
		_fill_toggle.set_pressed_no_signal(on)


## One line for what the type does on hit, from the authored [AmmoType].
static func effect_line(t: AmmoType) -> String:
	if t == null:
		return ""
	var parts: PackedStringArray = []
	# A zero scale is no damage payload (ADR 0033), so no "×0 dmg": a scout
	# reads as its rider alone.
	if not is_equal_approx(t.damage_scale, 1.0) and not is_zero_approx(t.damage_scale):
		parts.append("×%s dmg" % NumFmt.num(t.damage_scale))
	for effect in t.on_hit_effects:
		if effect == null:
			continue
		var line := effect.get_description()
		if not line.is_empty():
			parts.append(line)
	return " · ".join(parts) if not parts.is_empty() else "plain shot"


func _apply_min_size() -> void:
	custom_minimum_size = Vector2(min_width, roundf(min_width * aspect))


## The pile spans the stack; the bar covers its leading [member pile_cover].
func _layout_stack() -> void:
	if _stack == null:
		return
	var s := _stack.size
	_pile.position = Vector2.ZERO
	_pile.size = s
	_send_bar.position = Vector2.ZERO
	_send_bar.size = Vector2(roundf(s.x * pile_cover), s.y)


func _paint() -> void:
	if type == null:
		return
	_name_label.text = type.display_name
	_paint_status()
	_stock_label.text = ("%d  +%d" % [stock, gain]) if gain > 0 else "%d" % stock
	_count_label.text = "%d" % count
	# The volley bar's tint for this type, so a card reads as its bar segment.
	var tint: Color = VolleyBar.TYPE_TINTS.get(type.id, VolleyBar.FALLBACK_TINT)
	_send_bar.stock = stock
	_send_bar.value = count
	_send_bar.tint = tint
	_pile.count = stock
	_pile.tint = tint
	_fill_toggle.set_pressed_no_signal(fill)
	tooltip_text = "%s — %s" % [type.display_name, effect_line(type)]


## The type's status mark: the [IdentityBadge] of its first status rider
## ([method AmmoType.first_status_def]). A type with no status shows none.
func _paint_status() -> void:
	var def: StatusDef = type.first_status_def()
	_status_badge.identity = def.identity if def else null
	_status_badge.visible = _status_badge.identity != null


func _on_bar_requested(n: int) -> void:
	if type != null:
		set_requested.emit(type.id, n)


func _on_fill_toggled(on: bool) -> void:
	fill_toggled.emit(on)


func _on_count_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if type == null or mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		all_requested.emit(type.id)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		none_requested.emit(type.id)
	else:
		return
	_count_label.accept_event()
