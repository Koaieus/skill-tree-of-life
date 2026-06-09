extends Button

@export_color_no_alpha var tint: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var glow_radius: float = 0.3

const ANIMATION_TIME: float = 0.2

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var _mat: ShaderMaterial = color_rect.material as ShaderMaterial

var _hover_tweener: Tween
var _active_tweener: Tween
var _disabled_tweener: Tween

var hovered: float = 0.0:
	set(value):
		hovered = value
		if _mat: _mat.set_shader_parameter("glow_strength", value)

var active: float = 0.0:
	set(value):
		active = value
		if _mat: _mat.set_shader_parameter("active_strength", value)
		
var _disabled: float = 0.0:
	set(value):
		_disabled = value
		print("_disabled =", value)
		if _mat: _mat.set_shader_parameter("disabled_strength", value)

func _ready() -> void:
	label.text = text
	text = ""
	_set_disabled.call_deferred(disabled)
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("glow_radius", glow_radius)
	if _mat: _mat.set_shader_parameter('texture_size', size)


func _process(_delta: float) -> void:
	var uv := get_local_mouse_position() / size
	_mat.set_shader_parameter("mouse_uv", uv)

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
	if _mat: _mat.set_shader_parameter('texture_size', size)
