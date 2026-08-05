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

## Which borders the glow lights. Bit flags (Top=1, Right=2, Bottom=4,
## Left=8); default 15 = all four, matching the original uniform rim.
@export_flags("Top", "Right", "Bottom", "Left") var glow_edges: int = 15:
	set(v):
		glow_edges = v
		_push(&"glow_edges", v)

## How wide the glow hands over between the two edges meeting at a corner,
## in boundary-normal space. 0 = a hard switch at the corner's 45° bisector.
## Only observable when [member glow_edges] lights some but not all four.
@export_range(0.0, 1.0, 0.01) var glow_corner_softness: float = 0.35:
	set(v):
		glow_corner_softness = v
		_push(&"glow_corner_softness", v)

func _ready() -> void:
	if material == null:
		material = preload("res://ui/theme/holo_panel_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push(&"glow", glow)
	_push(&"glow_edges", glow_edges)
	_push(&"glow_corner_softness", glow_corner_softness)

func _push_size() -> void:
	_push(&"size", size)

func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
