@tool
class_name FusedPanel
extends ColorRect
## Fused "Arcane Terminal" panel: dark fill with optional gradient, animated
## scanlines, per-edge glow, hairline border, and sharp corner AA.
## Combines the best of GlassPanel (dark readability, gradient, border) and
## HoloPanel (scanlines, glow edge, CRT aesthetic).
##
## All exported values push to the shader immediately (and in-editor) so
## tuning is live in the Inspector.

# --- Fill ---

@export var fill_color: Color = Color(0.086, 0.098, 0.149, 0.90):
	set(v):
		fill_color = v
		_push(&"fill_color", v)

@export var gradient_color_b: Color = Color(0.039, 0.043, 0.075, 0.95):
	set(v):
		gradient_color_b = v
		_push(&"gradient_color_b", v)

@export_range(0.0, 360.0, 0.5) var gradient_angle_deg: float = 158.0:
	set(v):
		gradient_angle_deg = v
		_push(&"gradient_angle_deg", v)

## 0 = flat fill, 1 = full gradient between fill_color and gradient_color_b.
@export_range(0.0, 1.0, 0.01) var gradient_mix: float = 0.0:
	set(v):
		gradient_mix = v
		_push(&"gradient_mix", v)

# --- Scanlines ---

@export_range(10.0, 200.0, 1.0) var scanline_count: float = 60.0:
	set(v):
		scanline_count = v
		_push(&"scanline_count", v)

@export_range(0.0, 2.0, 0.01) var scanline_speed: float = 0.35:
	set(v):
		scanline_speed = v
		_push(&"scanline_speed", v)

@export_range(0.0, 1.0, 0.01) var scanline_intensity: float = 0.18:
	set(v):
		scanline_intensity = v
		_push(&"scanline_intensity", v)

# --- Edge glow ---

@export var glow_color: Color = Color(0.4, 0.95, 1.0, 1.0):
	set(v):
		glow_color = v
		_push(&"glow_color", v)

@export_range(0.0, 1.0, 0.01) var glow: float = 0.0:
	set(v):
		glow = v
		_push(&"glow", v)

## Which borders the glow lights. Bit flags (Top=1, Right=2, Bottom=4,
## Left=8); default 15 = all four.
@export_flags("Top", "Right", "Bottom", "Left") var glow_edges: int = 15:
	set(v):
		glow_edges = v
		_push(&"glow_edges", v)

## Width of the edge glow stroke in pixels.
@export_range(1.0, 12.0, 0.5) var glow_width: float = 2.0:
	set(v):
		glow_width = v
		_push(&"glow_width", v)

# --- Border ---

@export var border_color: Color = Color(0.47, 0.55, 0.75, 0.16):
	set(v):
		border_color = v
		_push(&"border_color", v)

@export_range(0.0, 8.0, 0.1) var border_width: float = 1.0:
	set(v):
		border_width = v
		_push(&"border_width", v)

# --- Corner ---

@export_range(0.0, 40.0, 0.5) var corner_radius: float = 13.0:
	set(v):
		corner_radius = v
		_push(&"corner_radius", v)

## How wide the edge glow hands over between the two edges meeting at a
## corner, measured in boundary-normal space. 0 = a hard switch at the corner's
## 45° bisector; 1 = the hand-over spans the whole arc. Only observable when
## [member glow_edges] lights some but not all four edges — with all four on,
## the selection sums to 1 around the whole boundary regardless.
@export_range(0.0, 1.0, 0.01) var glow_corner_softness: float = 0.35:
	set(v):
		glow_corner_softness = v
		_push(&"glow_corner_softness", v)


func _ready() -> void:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = preload("res://ui/theme/fused_panel.gdshader")
		material.resource_local_to_scene = true
	resized.connect(_push_size)
	_push_size()
	_push_all()


func _push_size() -> void:
	_push(&"size", size)


func _push_all() -> void:
	_push(&"fill_color", fill_color)
	_push(&"gradient_color_b", gradient_color_b)
	_push(&"gradient_angle_deg", gradient_angle_deg)
	_push(&"gradient_mix", gradient_mix)
	_push(&"scanline_count", scanline_count)
	_push(&"scanline_speed", scanline_speed)
	_push(&"scanline_intensity", scanline_intensity)
	_push(&"glow_color", glow_color)
	_push(&"glow", glow)
	_push(&"glow_edges", glow_edges)
	_push(&"glow_width", glow_width)
	_push(&"border_color", border_color)
	_push(&"border_width", border_width)
	_push(&"corner_radius", corner_radius)
	_push(&"glow_corner_softness", glow_corner_softness)


func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
