class_name LaunchAttackButton
extends Button

## Commits the current attack plan. Enabled by UIRoot iff there's a plan and
## it [method AttackPlan.is_valid]; pressed routes to
## [method BattleSystem.launch_attack].
##
## Visible always (no auto-hide) so the player sees the affordance even when
## there's nothing to launch — disabled grey state telegraphs "you need a
## target", enabled state lights up with a procedural fire shader because
## the running gag on this project is that every button gets ridiculous.
##
## Material pipeline mirrors [AttackModeButton]: one [ShaderMaterial] on the
## bg [ColorRect], one on the [Label], both fed by the same `_push()` so
## param names match across shaders. Tweens drive `hovered` / `active` /
## `_disabled` smoothly so state changes don't snap.

const TEXT_SHADER := preload("res://ui/attack_mode_bar/attack_mode_button_text.gdshader")
const ANIMATION_TIME: float = 0.25

@export_color_no_alpha var tint: Color = Color(1.0, 0.55, 0.1)
@export_color_no_alpha var hot_color: Color = Color(1.0, 1.0, 0.7)

var _text_mat := ShaderMaterial.new()
var _materials: Array[ShaderMaterial] = []

var _hover_tweener: Tween
var _active_tweener: Tween
var _disabled_tweener: Tween

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var _bg_mat: ShaderMaterial = color_rect.material as ShaderMaterial


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
## native `disabled` and drives the shader tweens. See AttackModeButton's
## comment on why this exists (direct `disabled =` writes bypass the tween).
var enabled: bool = true: set = set_enabled


func set_enabled(value: bool) -> void:
	enabled = value
	disabled = not value
	_tween_disabled(float(not value))
	_tween_active(1.0 if value else 0.0)


func _ready() -> void:
	update_label_text()

	_text_mat.shader = TEXT_SHADER
	label.material = _text_mat
	_materials = [_bg_mat, _text_mat]

	_push("tint", tint)
	_push("hot_color", hot_color)
	_push("texture_size", size)
	enabled = not disabled    # snap GDScript var to .tscn-set Button.disabled


func _push(param: String, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(param, value)


func update_label_text() -> void:
	if not label: return
	if label.text != text:
		label.text = text


func _process(_delta: float) -> void:
	_push("mouse_uv", get_local_mouse_position() / size)


func _tween_hover(to: float) -> void:
	if _hover_tweener: _hover_tweener.kill()
	_hover_tweener = create_tween()
	_hover_tweener.tween_property(self, "hovered", to, ANIMATION_TIME)


func _tween_active(to: float) -> void:
	if _active_tweener: _active_tweener.kill()
	_active_tweener = create_tween()
	_active_tweener.tween_property(self, "active", to, ANIMATION_TIME)


func _tween_disabled(to: float) -> void:
	if _disabled_tweener: _disabled_tweener.kill()
	_disabled_tweener = create_tween()
	_disabled_tweener.tween_property(self, "_disabled", to, ANIMATION_TIME)


func _on_mouse_entered() -> void:
	_tween_hover(1.0)


func _on_mouse_exited() -> void:
	_tween_hover(0.0)


func _on_resized() -> void:
	_push("texture_size", size)
