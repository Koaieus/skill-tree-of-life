extends Button

const TEXT_SHADER := preload("res://ui/action_bar/action_toggle_button_text.gdshader")

@export_color_no_alpha var tint: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var glow_radius: float = 0.3

const ANIMATION_TIME: float = 0.2

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var _bg_mat: ShaderMaterial = color_rect.material as ShaderMaterial

var _text_mat := ShaderMaterial.new()
var _materials: Array[ShaderMaterial] = []

var _hover_tweener: Tween
var _active_tweener: Tween
var _disabled_tweener: Tween

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

func _ready() -> void:
	label.text = text
	text = ""

	_text_mat.shader = TEXT_SHADER
	label.material = _text_mat
	_materials = [_bg_mat, _text_mat]

	_push("tint", tint)
	_push("glow_radius", glow_radius)
	_push("texture_size", size)
	_set_disabled.call_deferred(disabled)

func _push(param: String, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(param, value)

func _process(_delta: float) -> void:
	_push("mouse_uv", get_local_mouse_position() / size)

func _set_disabled(is_disabled: bool) -> void:
	disabled = is_disabled
	_tween_disabled(float(is_disabled))

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
