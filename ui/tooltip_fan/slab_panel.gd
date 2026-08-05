@tool
class_name SlabPanel
extends ColorRect

## The [ModSlabRow] background: dark fill, bright stat-tint border, soft tint
## glow (#343). One tuneable colour ([member tint_color]) with design knobs for
## fill darkness and glow strength — mirrors FusedPanel's push-to-shader
## pattern, scaled down for a 22px-tall reading row.

@export var tint_color: Color = Color(0.4, 0.95, 1.0):
	set(v):
		tint_color = v
		_push(&"tint_color", v)

## 0 = fill is the raw tint, 1 = fill is near-black.
@export_range(0.0, 1.0, 0.01) var fill_darkness: float = 0.88:
	set(v):
		fill_darkness = v
		_push(&"fill_darkness", v)

## 0 = hairline border, no halo; 1 = strong glow.
@export_range(0.0, 1.0, 0.01) var glow_strength: float = 0.5:
	set(v):
		glow_strength = v
		_push(&"glow_strength", v)

## Width of the bright inner border band, in pixels.
@export_range(0.5, 4.0, 0.1) var border_width: float = 1.5:
	set(v):
		border_width = v
		_push(&"border_width", v)

@export_range(0.0, 12.0, 0.5) var corner_radius: float = 4.0:
	set(v):
		corner_radius = v
		_push(&"corner_radius", v)


func _ready() -> void:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = preload("res://ui/tooltip_fan/slab_panel.gdshader")
		material.resource_local_to_scene = true
	resized.connect(_push_size)
	_push_size()
	_push_all()


func _push_size() -> void:
	_push(&"size", size)


func _push_all() -> void:
	_push(&"tint_color", tint_color)
	_push(&"fill_darkness", fill_darkness)
	_push(&"glow_strength", glow_strength)
	_push(&"border_width", border_width)
	_push(&"corner_radius", corner_radius)


func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
