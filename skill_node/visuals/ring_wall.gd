@tool
extends SkillNodeRingVisual
## Ring wall (#125): single structural wall ring built from 4 radii — pit
## (recessed floor), disc (flush with pit), crest (bevel inset), rim (outer
## edge). The crest->rim bevel look is a REAL height(radius) bumpmap lit by
## ring_wall.gdshader (fragment-side, not a CPU-banded fake) —
## level/terrace/smooth/sharpen are 4 closed-form presets baked into the
## shader itself, so every built-in-preset ring_wall shares ONE
## ShaderMaterial (batches into one draw call) while still varying per-node
## via `instance uniform`s. "No crest" = crest_r == rim_r; that alone
## collapses the band to nothing, no separate code path needed.
##
## Assigning a genuinely custom [Curve] to [member rim_height_style] (a
## 5th/6th profile) opts THIS instance out of the shared/batched material —
## samplers can't be instance uniforms, so a custom curve gets baked into a
## small LUT texture on a dedicated per-instance material instead. That's a
## deliberate, documented, opt-in cost for the escape hatch; the common
## (preset) path stays batched.
##
## Reusable building block: the composite scene (#126) instances this 1x
## for the basic rim, or Nx for ring-stacking stake mode.

enum HeightPreset { LEVEL, TERRACE, SMOOTH, SHARPEN }
const CUSTOM_PRESET_INDEX := 4
const LUT_SAMPLES := 64

const SHADER := preload("res://skill_node/visuals/ring_wall.gdshader")
const BASE_COLOR := Color(0.65, 0.67, 0.72)

## Shared across every ring_wall using a built-in preset — see the class
## doc. Built lazily so @tool previews and runtime both get it.
static var _shared_material: ShaderMaterial

## Recessed floor radius (informational at this layer — the inner disk owns
## the actual pit/disc rendering; carried here so the composite can read a
## single source of truth for all 4 rim radii).
@export var geom_pit_r: float = 24.0:
	set(value):
		geom_pit_r = value
		queue_redraw()
@export var geom_disc_r: float = 24.0:
	set(value):
		geom_disc_r = value
		queue_redraw()
@export var geom_crest_r: float = 28.0:
	set(value):
		geom_crest_r = value
		_sync_material()
@export var geom_rim_r: float = 32.0:
	set(value):
		geom_rim_r = value
		_sync_material()

## Assigning a Curve here that ISN'T one of the 4 built-in presets opts this
## instance out of the shared/batched material (see class doc). Set back to
## null (or change [member height_preset]) to return to the fast path.
@export var rim_height_style: Curve = null:
	set(value):
		rim_height_style = value
		_use_custom_curve = value != null
		_sync_material()

## Selects one of the 4 locked presets — the fast, batched path.
@export var height_preset: HeightPreset = HeightPreset.LEVEL:
	set(value):
		height_preset = value
		_use_custom_curve = false
		rim_height_style = null
		_sync_material()

@export var wall_color: Color = BASE_COLOR:
	set(value):
		wall_color = value
		_sync_material()

var _use_custom_curve: bool = false
var _custom_material: ShaderMaterial


func _ready() -> void:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = SHADER
	_sync_material()


func _sync_material() -> void:
	if not is_node_ready():
		return
	if _use_custom_curve and rim_height_style != null:
		if _custom_material == null:
			_custom_material = ShaderMaterial.new()
			_custom_material.resource_local_to_scene = true
			_custom_material.shader = SHADER
		material = _custom_material
		_custom_material.set_shader_parameter(&"height_lut", _bake_lut(rim_height_style))
		_custom_material.set_shader_parameter(&"crest_r", geom_crest_r)
		_custom_material.set_shader_parameter(&"rim_r", geom_rim_r)
		_custom_material.set_shader_parameter(&"wall_tint", wall_color)
		_custom_material.set_shader_parameter(&"height_preset", CUSTOM_PRESET_INDEX)
	else:
		material = _shared_material
		set_instance_shader_parameter(&"crest_r", geom_crest_r)
		set_instance_shader_parameter(&"rim_r", geom_rim_r)
		set_instance_shader_parameter(&"wall_tint", wall_color)
		set_instance_shader_parameter(&"height_preset", int(height_preset))
	queue_redraw()


## Bakes a Curve to a small 1D LUT texture for the custom-curve fallback
## material (see class doc — samplers can't be instance uniforms).
static func _bake_lut(curve: Curve) -> ImageTexture:
	var img := Image.create(LUT_SAMPLES, 1, false, Image.FORMAT_RF)
	for x in LUT_SAMPLES:
		var t := float(x) / float(LUT_SAMPLES - 1)
		var h := clampf(curve.sample(t), 0.0, 1.0)
		img.set_pixel(x, 0, Color(h, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	# The shader draws the actual ring band; this quad just needs to cover
	# it (material is applied to whatever this draws).
	if geom_rim_r <= geom_crest_r:
		return
	draw_rect(Rect2(Vector2(-geom_rim_r, -geom_rim_r), Vector2.ONE * geom_rim_r * 2.0), Color.WHITE)
