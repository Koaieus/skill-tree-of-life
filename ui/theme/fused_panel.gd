@tool
class_name FusedPanel
extends ColorRect
## Fused "Arcane Terminal" panel: dark fill with optional gradient, animated
## scanlines, per-edge glow, hairline border, and sharp corner AA.
## Combines the best of GlassPanel (dark readability, gradient, border) and
## HoloPanel (scanlines, glow edge, CRT aesthetic).
##
## #391 split the shader's uniforms in two. Genuinely per-panel values (this
## node's rect [member ColorRect.size], [member glow], [member glow_edges],
## [member glow_energy]) are exported here and ride `instance uniform` /
## `set_instance_shader_parameter` on ONE shared [ShaderMaterial]
## ([method _shared_material]) — so every panel that doesn't author its own
## material batches into one draw call. Everything that was constant across
## every panel scene in practice (fill, gradient, scanlines, glow colour/width,
## border, corner) is baked into that shared material instead of being an
## `@export` here: the point of #391 is that those can no longer drift
## per-panel, so removing the knob is what makes the uniformity structural,
## not just a convention. Retune them by editing [method _shared_material].

# --- Edge glow (per-panel) ---

## How much of the glow stroke shows (0 = off). Animated at runtime — e.g.
## [FanPanel]'s idle pulse — so this has to be a live per-instance value, not
## a baked constant.
@export_range(0.0, 1.0, 0.01) var glow: float = 0.0:
	set(v):
		glow = v
		_push_instance(&"glow", v)

## Which borders the glow lights. Bit flags (Top=1, Right=2, Bottom=4,
## Left=8); default 15 = all four.
@export_flags("Top", "Right", "Bottom", "Left") var glow_edges: int = 15:
	set(v):
		glow_edges = v
		_push_instance(&"glow_edges", v)

## EV stops (see [Emissive]) that the shared material's `glow_color` is raised
## by before it's mixed into the border — the term #391 asked for so a panel's
## glow can clear the bloom pass's linear threshold instead of just reading as
## an SDR highlight. Defaults to [constant Emissive.VALUE].
@export_range(0.0, 3.0, 0.05) var glow_energy: float = Emissive.VALUE:
	set(v):
		glow_energy = v
		_push_instance(&"glow_energy", v)


func _ready() -> void:
	if material == null:
		material = _shared_material()
	resized.connect(_push_size)
	_push_size()
	_push_instance(&"glow", glow)
	_push_instance(&"glow_edges", glow_edges)
	_push_instance(&"glow_energy", glow_energy)


func _push_size() -> void:
	_push_instance(&"size", size)


## Per-panel values ride the instance-uniform interface — set on THIS
## CanvasItem, not on the (possibly shared) material — so panels sharing
## [method _shared_material] don't fight over one object's uniform state.
func _push_instance(param: StringName, value: Variant) -> void:
	set_instance_shader_parameter(param, value)


## One [ShaderMaterial], lazily built and cached at the class level, carrying
## every constant-across-every-panel uniform. Every [FusedPanel] that doesn't
## author its own `material` override in its scene shares this exact object,
## so they batch into one draw call (`.claude/rules/rendering-performance.md`)
## instead of each paying for a separate unbatchable material.
static var _cached_material: ShaderMaterial = null

static func _shared_material() -> ShaderMaterial:
	if _cached_material == null:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://ui/theme/fused_panel.gdshader")
		mat.set_shader_parameter(&"fill_color", Color(0.06, 0.13, 0.17, 0.85))
		mat.set_shader_parameter(&"gradient_color_b", Color(0.039, 0.043, 0.075, 0.95))
		mat.set_shader_parameter(&"gradient_angle_deg", 158.0)
		# #391 collapsed gradient_mix to one shared value; the fan's core_panel
		# was the only scene that had turned it on (1.0), the rest were at the
		# script's old default (0.0) only because nobody had touched the knob.
		# Picking core_panel's value means every panel now gets the richer
		# gradient fill uniformly, rather than flattening the one panel that
		# used it — worth an eyeball pass on id_chip_panel/addons_panel.
		mat.set_shader_parameter(&"gradient_mix", 1.0)
		mat.set_shader_parameter(&"scanline_pitch", 1.6)
		mat.set_shader_parameter(&"scanline_speed", 0.35)
		mat.set_shader_parameter(&"scanline_intensity", 0.09)
		mat.set_shader_parameter(&"glow_color", Color(0.4, 0.95, 1.0, 1.0))
		mat.set_shader_parameter(&"glow_width", 2.0)
		mat.set_shader_parameter(&"border_color", Color(0.47, 0.55, 0.75, 0.16))
		mat.set_shader_parameter(&"border_width", 1.0)
		mat.set_shader_parameter(&"corner_radius", 13.0)
		mat.set_shader_parameter(&"glow_corner_softness", 0.35)
		_cached_material = mat
	return _cached_material
