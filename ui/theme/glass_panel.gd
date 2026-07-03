@tool
class_name GlassPanel
extends ColorRect
## Reusable "Arcane Terminal" glass panel: rounded rect, diagonal gradient
## fill, hairline border, optional inner glow. All exported values push to
## the shader immediately (and in-editor) so tuning is live in the Inspector.

@export var gradient_color_a: Color = Color(0.086, 0.098, 0.149, 0.94):
	set(v):
		gradient_color_a = v
		_push(&"gradient_color_a", v)

@export var gradient_color_b: Color = Color(0.039, 0.043, 0.075, 0.95):
	set(v):
		gradient_color_b = v
		_push(&"gradient_color_b", v)

@export_range(0.0, 360.0, 0.5) var gradient_angle_deg: float = 158.0:
	set(v):
		gradient_angle_deg = v
		_push(&"gradient_angle_deg", v)

@export var border_color: Color = Color(0.47, 0.55, 0.75, 0.16):
	set(v):
		border_color = v
		_push(&"border_color", v)

@export_range(0.0, 8.0, 0.1) var border_width: float = 1.0:
	set(v):
		border_width = v
		_push(&"border_width", v)

@export_range(0.0, 40.0, 0.5) var corner_radius: float = 13.0:
	set(v):
		corner_radius = v
		_push(&"corner_radius", v)

## Optional inner glow tint (e.g. the Hero Sigil Card's gold-tinted variant,
## or Combat Readout's per-mode highlight border). alpha 0 disables it.
@export var glow_color: Color = Color(1.0, 1.0, 1.0, 0.0):
	set(v):
		glow_color = v
		_push(&"glow_color", v)

@export_range(0.0, 40.0, 0.5) var glow_strength: float = 0.0:
	set(v):
		glow_strength = v
		_push(&"glow_strength", v)

func _ready() -> void:
	if material == null:
		material = preload("res://ui/theme/glass_panel_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push_all()

func _push_size() -> void:
	_push(&"size", size)

func _push_all() -> void:
	_push(&"gradient_color_a", gradient_color_a)
	_push(&"gradient_color_b", gradient_color_b)
	_push(&"gradient_angle_deg", gradient_angle_deg)
	_push(&"border_color", border_color)
	_push(&"border_width", border_width)
	_push(&"corner_radius", corner_radius)
	_push(&"glow_color", glow_color)
	_push(&"glow_strength", glow_strength)

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
