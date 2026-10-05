@tool
class_name AmmoCard
extends PanelContainer
## One row of the Quiver roster (#954): an [AmmoType]'s name, stock,
## `+N on reload`, its one-line effect, and — for a special — a stepper on
## its count in the volley. The base arrow is NOT a control (owner,
## 2026-09-19: base is the remainder `N − Σ specials`), so its card has no
## stepper. Pure view: it asks for changes through its signals.
##
## Stepper grammar: click ± = ±1, scroll on the card = ±1, Shift-click ± =
## all / none.

signal step_requested(type_id: StringName, delta: int)
signal set_requested(type_id: StringName, count: int)

## Edge length of the status badge.
@export_range(12, 64) var badge_px: int = 20:
	set(value):
		badge_px = value
		if _status_badge != null:
			_status_badge.size_px = value

var type: AmmoType = null
var stock: int = 0
var gain: int = 0
var count: int = 0
## The most this card may take: min(bin, what N can still hold).
var cap: int = 0

@onready var _name_label: Label = %NameLabel
@onready var _status_badge: IdentityBadge = %StatusBadge
@onready var _stock_label: Label = %StockLabel
@onready var _effect_label: Label = %EffectLabel
@onready var _stepper: HBoxContainer = %Stepper
@onready var _count_label: Label = %CountLabel
@onready var _minus: Button = %Minus
@onready var _plus: Button = %Plus


func _ready() -> void:
	_minus.pressed.connect(_on_minus)
	_plus.pressed.connect(_on_plus)
	_minus.gui_input.connect(_on_step_button_input.bind(-1))
	_plus.gui_input.connect(_on_step_button_input.bind(1))
	gui_input.connect(_on_gui_input)
	_status_badge.size_px = badge_px
	_paint()


func setup(p_type: AmmoType) -> void:
	type = p_type
	if is_node_ready():
		_paint()


func has_stepper() -> bool:
	return type != null and type.id != AmmoTypeRoster.BASE_ID


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


func _paint() -> void:
	if type == null:
		return
	_name_label.text = type.display_name
	_paint_status()
	var stock_text := "stock %d" % stock
	if gain > 0:
		stock_text += " · +%d on reload" % gain
	_stock_label.text = stock_text
	_effect_label.text = effect_line(type)
	_stepper.visible = has_stepper()
	_count_label.text = "%d" % count
	_minus.disabled = count <= 0
	_plus.disabled = count >= cap
	tooltip_text = "%s — %s" % [type.display_name, _effect_label.text]


## The type's status mark: the [IdentityBadge] of its first status rider
## ([method AmmoType.first_status_def]). A type with no status shows none.
func _paint_status() -> void:
	var def: StatusDef = type.first_status_def()
	_status_badge.identity = def.identity if def else null
	_status_badge.visible = _status_badge.identity != null


func _on_minus() -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		set_requested.emit(type.id, 0)
	else:
		step_requested.emit(type.id, -1)


func _on_plus() -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		set_requested.emit(type.id, cap)
	else:
		step_requested.emit(type.id, 1)


## Scrolling over a ± button steps too, so the wheel works anywhere on the card.
func _on_step_button_input(event: InputEvent, _sign: int) -> void:
	_on_gui_input(event)


func _on_gui_input(event: InputEvent) -> void:
	if not has_stepper() or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		step_requested.emit(type.id, 1)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step_requested.emit(type.id, -1)
		accept_event()
