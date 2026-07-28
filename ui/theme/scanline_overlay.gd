@tool
class_name ScanlineOverlay
extends ColorRect
## Hosts `holo_scanline_overlay.gdshader` (#226) — the shader existed unhosted
## ("Host on a ColorRect sized to the panel... `size` is pushed by the host",
## per the shader's own header comment) until the Tooltip V2 z-sandwich
## needed it as the top layer. Mirrors GlassPanel/HoloPanel's push-to-shader
## pattern exactly: `mouse_filter = IGNORE`, push `size` on resize, push the
## color/authoring exports once at `_ready`.
##
## Meant to sit as the LAST child (or `z_index = 1`) above a panel's content,
## per the "z-sandwich": HoloPanel background z=-1, content z=0, this z=+1.

@export var line_color: Color = Color(0.4, 0.95, 1.0, 1.0):
	set(v):
		line_color = v
		_push(&"line_color", v)

@export_range(0.0, 40.0, 0.5) var corner_radius: float = 13.0:
	set(v):
		corner_radius = v
		_push(&"corner_radius", v)

@export_range(1.0, 300.0, 1.0) var scanline_count: float = 90.0:
	set(v):
		scanline_count = v
		_push(&"scanline_count", v)

@export_range(0.0, 4.0, 0.01) var scanline_speed: float = 0.4:
	set(v):
		scanline_speed = v
		_push(&"scanline_speed", v)

@export_range(0.0, 1.0, 0.01) var scanline_intensity: float = 0.22:
	set(v):
		scanline_intensity = v
		_push(&"scanline_intensity", v)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if material == null:
		material = preload("res://ui/theme/holo_scanline_overlay_material.tres").duplicate()
	resized.connect(_push_size)
	_push_size()
	_push(&"line_color", line_color)
	_push(&"corner_radius", corner_radius)
	_push(&"scanline_count", scanline_count)
	_push(&"scanline_speed", scanline_speed)
	_push(&"scanline_intensity", scanline_intensity)


func _push_size() -> void:
	_push(&"size", size)


func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
