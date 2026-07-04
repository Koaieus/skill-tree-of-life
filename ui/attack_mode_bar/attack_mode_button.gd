@tool
class_name AttackModeButton
extends Button

const TEXT_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button_text.gdshader")
const ANIMATION_TIME: float = 0.2

@export_color_no_alpha var tint: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var glow_radius: float = 0.3

@export var attack_mode: BattleSystem.AttackMode

## Keyboard shortcut chip text shown in the tab's top-left corner (e.g.
## "1", "Q") — purely cosmetic, doesn't drive the actual [member shortcut].
@export var key_hint: String = "":
	set(v):
		key_hint = v
		if _key_label != null:
			_key_label.text = v

var _text_mat := ShaderMaterial.new()
var _materials: Array[ShaderMaterial] = []


var _hover_tweener: Tween
var _active_tweener: Tween
var _disabled_tweener: Tween

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var _bg_mat: ShaderMaterial = color_rect.material as ShaderMaterial
@onready var _key_chip: PanelContainer = $KeyChip
@onready var _key_label: Label = $KeyChip/KeyLabel


var hovered: float = 0.0:
	set(value):
		hovered = value
		_push("glow_strength", value)

var active: float = 0.0:
	set(value):
		active = value
		_push("active_strength", value)

var _disabled: float = 0.0:
	set(value):
		_disabled = value
		_push("disabled_strength", value)

## Sole write-path for the button's enabled state. Mirrors to the engine's
## native `disabled` and runs the visual tween. Use `btn.enabled = X` at call
## sites — direct `disabled = X` writes would bypass the tween (engine writes
## to the native property can't be intercepted from GDScript).
var enabled: bool = true: set = set_enabled

func set_enabled(value: bool) -> void:
	enabled = value
	disabled = not value
	_tween_disabled(float(not value))

func _ready() -> void:
	update_label_text()

	_text_mat.shader = TEXT_SHADER
	label.material = _text_mat
	_materials = [_bg_mat, _text_mat]

	_push("tint", tint)
	_push("glow_radius", glow_radius)
	_push("texture_size", size)
	enabled = not disabled    # snap GDScript var to .tscn-set Button.disabled

	if _key_chip != null:
		var sb: StyleBoxFlat = _key_chip.get_theme_stylebox(&"panel").duplicate()
		sb.border_color = tint
		_key_chip.add_theme_stylebox_override(&"panel", sb)
	if _key_label != null:
		_key_label.modulate = tint
		_key_label.text = key_hint

func _push(param: String, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(param, value)


func override_toggle(toggled: bool) -> void:
	active = toggled
	set_pressed_no_signal(toggled)

func update_label_text() -> void:
	if not label: return
	if label.text != text:
		label.text = text
		
	
func _process(_delta: float) -> void:
	_push("mouse_uv", get_local_mouse_position() / size)

func _tween_disabled(to: float) -> void:
	if _disabled_tweener: _disabled_tweener.kill()
	_disabled_tweener = create_tween()
	_disabled_tweener.tween_property(self, "_disabled", to, ANIMATION_TIME)

func _tween_hover(to: float) -> void:
	if _hover_tweener: _hover_tweener.kill()
	_hover_tweener = create_tween()
	_hover_tweener.tween_property(self, "hovered", to, ANIMATION_TIME)

func _tween_active(to: float) -> void:
	if _active_tweener: _active_tweener.kill()
	_active_tweener = create_tween()
	_active_tweener.tween_property(self, "active", to, ANIMATION_TIME)

func _on_mouse_entered() -> void:
	_tween_hover(1.0)

func _on_mouse_exited() -> void:
	_tween_hover(0.0)

func _on_toggled(toggled_on: bool) -> void:
	_tween_active(float(toggled_on))

func _on_resized() -> void:
	_push("texture_size", size)
