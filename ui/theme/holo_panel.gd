@tool
class_name HoloPanel
extends ColorRect
## Reusable "Arcane Terminal" hologram panel: animated scanlines, translucent
## hologram tint, and rim glow. Mirrors GlassPanel's push-to-shader pattern
## (see ui/theme/glass_panel.gd) but exposes a single tunable: `glow`.

@export_range(0.0, 1.0, 0.01) var glow: float = 0.0:
	set(v):
		glow = v
		_push(&"glow", v)

func _ready() -> void:
	if material == null:
		material = preload("res://ui/theme/holo_panel_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push(&"glow", glow)

func _push_size() -> void:
	_push(&"size", size)

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
