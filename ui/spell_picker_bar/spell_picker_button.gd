@tool
class_name SpellPickerButton
extends Button

## A single spell pick in [SpellPickerBar]. Toggle button (radio-managed by
## the bar's ButtonGroup) that renders a spell card:
##   * top inset — one tick per [member SpellDef.min_degree]
##   * icon (or letter glyph fallback)
##   * name + mana cost label
##
## State plumbing uses Godot's standard [member Button.disabled] /
## [signal Button.toggled] machinery — no custom shader needed for v1; the
## attack-mode-bar shader can be lifted in if/when the polish bar rises.
## "Castable from current source" lives in [method set_castable] which just
## flips [member Button.disabled] so all visual states cascade for free.

const _TICK_W: float = 6.0
const _TICK_H: float = 3.0
const _TICK_GAP: float = 3.0
const _TICK_TINT := Color(0.55, 0.85, 1.0, 0.95)
const _LETTER_FONT_SIZE: int = 28

@export var spell: SpellDef = null:
	set(value):
		spell = value
		_apply_spell()

@onready var _ticks: HBoxContainer = $VBox/Ticks
@onready var _icon_rect: TextureRect = $VBox/Icon
@onready var _name_label: Label = $VBox/NameLabel
@onready var _letter_label: Label = $VBox/Icon/LetterLabel


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(96, 96)
	clip_text = true
	_apply_spell()


func set_castable(castable: bool) -> void:
	disabled = not castable


## Wired in [_apply_spell]; exposed so callers can rebuild if they mutate the
## SpellDef in place (rare — usually a fresh spell instance gets assigned).
func refresh() -> void:
	_apply_spell()


func _apply_spell() -> void:
	if not is_node_ready():
		return
	if spell == null:
		_name_label.text = ""
		_icon_rect.texture = null
		_letter_label.text = ""
		_clear_ticks()
		return
	_name_label.text = "%s (%d)" % [spell.name, spell.mana_cost]
	tooltip_text = _tooltip_for(spell)
	if spell.icon != null:
		_icon_rect.texture = spell.icon
		_letter_label.visible = false
	else:
		_icon_rect.texture = null
		_letter_label.visible = true
		_letter_label.text = spell.name.substr(0, 1).to_upper() if spell.name != "" else "?"
	_rebuild_ticks(spell.min_degree)


func _clear_ticks() -> void:
	for c in _ticks.get_children():
		c.queue_free()


func _rebuild_ticks(n: int) -> void:
	_clear_ticks()
	for i in maxi(0, n):
		var tick := ColorRect.new()
		tick.color = _TICK_TINT
		tick.custom_minimum_size = Vector2(_TICK_W, _TICK_H)
		_ticks.add_child(tick)


func _tooltip_for(s: SpellDef) -> String:
	var lines: Array[String] = []
	lines.append("%s — %d mana" % [s.name, s.mana_cost])
	lines.append("Requires node degree ≥ %d" % s.min_degree)
	if s.description != "":
		lines.append(s.description)
	if s.propagation != null:
		var prop := s.propagation.get_description()
		if prop != "":
			lines.append(prop)
	return "\n".join(lines)
