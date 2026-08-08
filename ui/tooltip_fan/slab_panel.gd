@tool
class_name SlabPanel
extends ColorRect

## The [ModSlabRow] background: dark fill, bright stat-tint border, soft tint
## glow (#343). One tuneable colour ([member tint_color]) with design knobs for
## fill darkness and glow strength — mirrors FusedPanel's push-to-shader
## pattern, scaled down for a 22px-tall reading row.


@onready var label: Label = %Label


@export var tint_color: Color = Color(0.4, 0.95, 1.0):
	set(v):
		tint_color = v
		if label:
			label.add_theme_color_override(&"font_color", v)
		_push(&"tint_color", v)

## 0 = fill is the raw tint, 1 = fill is near-black.
@export_range(0.0, 1.0, 0.01) var fill_darkness: float = 0.88:
	set(v):
		fill_darkness = v
		_push(&"fill_darkness", v)

## 0 = stroke invisible, 1 = fully blended in. Opacity only — see
## [member glow_energy] for whether the stroke actually blooms.
@export_range(0.0, 1.0, 0.01) var glow_strength: float = 0.5:
	set(v):
		glow_strength = v
		_push(&"glow_strength", v)

## EV stops (see [Emissive]) the stroke is lifted by, via [method Emissive.tint]
## (luminance-normalized, so equal stops read as equal glow across different
## stat hues — see the shader's own copy of this formula). Defaults to
## [constant Emissive.VALUE].
@export_range(0.0, 3.0, 0.05) var glow_energy: float = Emissive.VALUE:
	set(v):
		glow_energy = v
		_push(&"glow_energy", v)

## How deep the bright inward stroke fades, in pixels. Judge against the
## rendered pixel footprint, not what merely looks right zoomed in — see
## docs/domain/hdr-color.md's pixel-coverage-floor section.
@export_range(0.5, 8.0, 0.1) var glow_width: float = 2.5:
	set(v):
		glow_width = v
		_push(&"glow_width", v)

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
	_push(&"glow_energy", glow_energy)
	_push(&"glow_width", glow_width)
	_push(&"corner_radius", corner_radius)


func _push(param: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(param, value)
