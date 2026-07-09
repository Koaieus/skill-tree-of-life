@tool
extends SkillNodeRingVisual
## Rim ring (#125): the raised chrome/gem-holder band around a SkillNode's
## disk — NOT a "wall" (renamed from RingWall), and it knows nothing about
## the disk beneath it. It only owns its own band: [member inner_radius]
## (base class) to [member outer_radius] (base class), with [member crest_r]
## as an *interior* control point marking where the flat floor ends and the
## bevel to the rim begins. The composite is responsible for lining
## [member inner_radius] up with whatever disk radius it's wrapping.
##
## The crest->rim bevel is a REAL height(radius) bumpmap lit by
## rim_ring.gdshader (fragment-side, not a CPU-banded fake) —
## level/terrace/smooth/sharpen are 4 closed-form presets baked into the
## shader itself, so every built-in-preset rim_ring shares ONE
## ShaderMaterial (batches into one draw call) while still varying per-node
## via `instance uniform`s. "No bevel" = crest_r == outer_radius, which
## collapses the whole band to a flat plateau; crest_r == inner_radius
## bevels the entire band with no flat floor segment.
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

enum HeightPreset { LEVEL, TERRACE, SMOOTH, SHARPEN, CUSTOM }
const CUSTOM_PRESET_INDEX := 4
const LUT_SAMPLES := 64

const SHADER := preload("res://skill_node/visuals/rim_ring.gdshader")
const BASE_COLOR := Color(0.65, 0.67, 0.72)

## Shared across every rim_ring using a built-in preset — see the class
## doc. Built lazily so @tool previews and runtime both get it.
static var _shared_material: ShaderMaterial

## Interior control point (inner_radius < crest_r <= outer_radius): where
## the flat floor ends and the bevel toward the rim begins.
@export_range(0.0, 128.0, 0.5) var crest_r: float = 28.0:
	set(value):
		crest_r = value
		_sync_material()

## Assigning a Curve here that ISN'T one of the 4 built-in presets opts this
## instance out of the shared/batched material (see class doc). Set back to
## null (or change [member height_preset]) to return to the fast path.
## We connect to the Curve's own `changed` signal so dragging its points in the
## inspector re-bakes the LUT live (the Curve edits in place — the setter here
## only fires on a whole-resource swap, not per point-drag).
@export var rim_height_style: Curve:
	set(value):
		if rim_height_style != null and rim_height_style.changed.is_connected(_on_curve_changed):
			rim_height_style.changed.disconnect(_on_curve_changed)
		rim_height_style = value
		if rim_height_style != null and not rim_height_style.changed.is_connected(_on_curve_changed):
			rim_height_style.changed.connect(_on_curve_changed)
		# Assigning a real Curve directly (not via height_preset) is itself
		# what makes this instance custom — keep height_preset's inspector
		# display in sync rather than requiring both to be set by hand.
		if rim_height_style != null:
			height_preset = CUSTOM_PRESET_INDEX
		_rebake_lut()
		_sync_material()

## Selects one of the 4 locked presets — the fast, batched path. Only clears
## [member rim_height_style] for non-custom presets: on scene load, exported
## props apply in declaration order, so [member rim_height_style] (declared
## above) is assigned BEFORE this setter runs (deserialized as CUSTOM when a
## custom curve was saved) — unconditionally nulling here wiped the just-loaded
## curve on every "reload saved scene" (bug: curve set, saved, reload → gone).
@export var height_preset: HeightPreset = HeightPreset.LEVEL:
	set(value):
		height_preset = value
		if value != CUSTOM_PRESET_INDEX:
			rim_height_style = null
		_sync_material()

## 0 = the ring's own metal color ([const BASE_COLOR], bronze/gold-ish); 1 =
## maximally mixed toward [member SkillNodeVisual.archetype_tint]. Lets the
## composer read as "mostly its own material, tinted by archetype" instead of a
## flat hue swap. The rim is structure, so it never reads `entity_tint`.
@export_range(0.0, 1.0, 0.01) var tint_mix: float = 0.0:
	set(value):
		tint_mix = value
		_sync_material()

## The actual color pushed to the shader — [const BASE_COLOR] lerped toward
## the archetype identity by [member tint_mix].
var _effective_tint: Color:
	get(): return BASE_COLOR.lerp(archetype_tint, tint_mix)

## Same value as InnerDisk.highlight_position — see #130. The composite
## forwards InnerDisk's value here so the disk and its rim stay lit from one
## source; a standalone preview just keeps the default.
@export var light_dir: Vector2 = Vector2(-0.35, -0.35):
	set(value):
		light_dir = value
		_sync_material()

## Shared light source (see [LightingStyle]) — runtime-injected plain `var`
## (NOT `@export`, per the @tool scene-baking gotcha), so the disk and its rim
## stay lit from ONE source. Null in a standalone preview.
var lighting: LightingStyle = null:
	set(value):
		if lighting != null and lighting.changed.is_connected(_apply_lighting):
			lighting.changed.disconnect(_apply_lighting)
		lighting = value
		if lighting != null and not lighting.changed.is_connected(_apply_lighting):
			lighting.changed.connect(_apply_lighting)
		_apply_lighting()

var _use_custom_curve: bool:
	get():
		return height_preset == CUSTOM_PRESET_INDEX and rim_height_style != null

var _custom_material: ShaderMaterial


func _apply_lighting() -> void:
	if lighting == null:
		return
	light_dir = lighting.highlight_position


func _on_identity_changed() -> void:
	_sync_material()


## Live-update hook for in-place Curve edits (dragging points in the inspector).
## Re-bakes the LUT only — radii/tint/preset are untouched, so this stays cheap.
func _on_curve_changed() -> void:
	_rebake_lut()
	queue_redraw()


## (Re)bakes the custom Curve into the per-instance material's height_lut. No-op
## unless a custom Curve is active. Kept OUT of _sync_material so the heavy
## texture rebuild only happens when the Curve itself changes — not on every
## crest_r / radius / tint tweak (that churn was interrupting inspector drags).
func _rebake_lut() -> void:
	if not _use_custom_curve or rim_height_style == null:
		return
	if _custom_material == null:
		_custom_material = ShaderMaterial.new()
		_custom_material.resource_local_to_scene = true
		_custom_material.shader = SHADER
	_custom_material.set_shader_parameter(&"height_lut", _bake_lut(rim_height_style))


func _on_ring_radius_changed() -> void:
	_sync_material()


func _ready() -> void:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = SHADER
	_sync_material()


func _sync_material() -> void:
	if not is_node_ready():
		return
	# The two paths differ ONLY in which material is bound (shared vs a
	# per-instance one carrying the custom LUT) and the height_preset value.
	# EVERYTHING varying per node — inner_r/crest_r/outer_r/ring_tint/
	# height_preset/light_dir_xy — is an `instance uniform`, so it MUST be set
	# via set_instance_shader_parameter() on the CanvasItem, NOT
	# material.set_shader_parameter() (that silently no-ops for instance
	# uniforms — the bug that made a custom rim_height_style Curve do nothing:
	# height_preset never reached CUSTOM_PRESET_INDEX so the LUT was never
	# sampled). The custom material exists ONLY to carry `height_lut`, a real
	# sampler uniform, which genuinely can't ride an instance uniform.
	# The LUT is (re)baked separately in _rebake_lut() — only on Curve change,
	# never here. Bind the right material, but ONLY reassign when it actually
	# changes: reassigning `material` every call churns a property the inspector
	# watches and interrupts slider drags (crest_r could only move in 0.5 steps).
	var use_custom := _use_custom_curve
	var target_mat: ShaderMaterial = _custom_material if use_custom else _shared_material
	if target_mat != null and material != target_mat:
		material = target_mat
	set_instance_shader_parameter(&"inner_r", inner_radius)
	set_instance_shader_parameter(&"crest_r", crest_r)
	set_instance_shader_parameter(&"outer_r", outer_radius)
	set_instance_shader_parameter(&"ring_tint", _effective_tint)
	set_instance_shader_parameter(&"height_preset", CUSTOM_PRESET_INDEX if use_custom else int(height_preset))
	set_instance_shader_parameter(&"light_dir_xy", light_dir)
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
	if outer_radius <= inner_radius:
		return
	draw_rect(Rect2(Vector2(-outer_radius, -outer_radius), Vector2.ONE * outer_radius * 2.0), Color.WHITE)
