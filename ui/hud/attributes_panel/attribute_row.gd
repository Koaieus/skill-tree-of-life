@tool
class_name AttributeRow
extends HBoxContainer
## One numeric attribute row (colored dot + label + big glowing value) in the
## Attributes Panel (#109). Glow scales with magnitude (shadow-outline halo,
## since Godot has no native text blur); values >= EMBER_THRESHOLD gain a
## slow brightness flicker. Hover drives [signal row_hovered] so the panel
## can show the shared [AttributeRules] tooltip — this row doesn't own it.

const EMBER_THRESHOLD := 40.0
const MAX_GLOW_VALUE := 60.0

signal row_hovered(attr_id: StringName)
signal row_unhovered(attr_id: StringName)

## Which StatBoard field this row reads — set per-instance in the composing
## scene (AttributesPanel.tscn), mirroring the DI-in-the-scene convention.
@export var attr_id: StringName = &""
@export var attr_label: String = "":
	set(v):
		attr_label = v
		if _label != null:
			_label.text = v

@export var tint_color: Color = Color.WHITE:
	set(v):
		tint_color = v
		if _dot != null:
			_dot.color = v
		if _value != null:
			_value.add_theme_color_override(&"font_color", v)
			_value.add_theme_color_override(&"font_shadow_color", Color(v.r, v.g, v.b, 0.7))

@onready var _dot: ColorRect = %Dot
@onready var _label: Label = %Label
@onready var _value: Label = %Value

var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): row_hovered.emit(attr_id))
	mouse_exited.connect(func(): row_unhovered.emit(attr_id))
	if _label != null:
		_label.text = attr_label
	if _dot != null:
		_dot.color = tint_color
	if _value != null:
		_value.add_theme_color_override(&"font_color", tint_color)


func set_value(v: float) -> void:
	if _value == null:
		return
	_value.text = str(int(v))
	var glow: int = int(clamp(4.0 + (v / MAX_GLOW_VALUE) * 10.0, 4.0, 14.0))
	_value.add_theme_constant_override(&"shadow_outline_size", glow)
	_set_ember(v >= EMBER_THRESHOLD)


func _set_ember(active: bool) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if not active:
		_value.modulate = Color.WHITE
		return
	_tween = create_tween().set_loops()
	_tween.tween_property(_value, ^"modulate", Color(1.3, 1.2, 1.0, 1.0), 0.9)
	_tween.tween_property(_value, ^"modulate", Color(1.0, 1.0, 1.0, 1.0), 0.9)
