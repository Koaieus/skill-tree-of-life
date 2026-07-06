@tool
extends SkillNodeRingVisual
## Ring wall (#125): single structural wall ring built from 4 radii — pit
## (recessed floor), disc (flush with pit), crest (bevel inset), rim (outer
## edge). The crest->rim bevel look is a height(radius) function (a `Curve`
## resource), not a fixed shape — level/terrace/smooth/sharpen are just 4
## presets of it. "No crest" = crest_r == rim_r; that alone collapses the
## band to nothing, no separate code path needed.
##
## Reusable building block: the composite scene (#126) instances this 1x for
## the basic rim, or Nx for ring-stacking stake mode.

enum HeightPreset { LEVEL, TERRACE, SMOOTH, SHARPEN }

const RING_STEPS := 28
const BASE_COLOR := Color(0.65, 0.67, 0.72)

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
		queue_redraw()
@export var geom_rim_r: float = 32.0:
	set(value):
		geom_rim_r = value
		queue_redraw()

## Swappable height(radius) function: normalized domain [0,1] (crest->rim)
## -> height [0,1], sampled per band for shading. Assign a custom Curve to
## add a 5th/6th profile without touching this script.
@export var rim_height_style: Curve = null:
	set(value):
		rim_height_style = value
		queue_redraw()

## Convenience: rebuilds rim_height_style from one of the 4 locked presets.
@export var height_preset: HeightPreset = HeightPreset.LEVEL:
	set(value):
		height_preset = value
		rim_height_style = _build_preset(value)

@export var wall_color: Color = BASE_COLOR:
	set(value):
		wall_color = value
		queue_redraw()


func _ready() -> void:
	if rim_height_style == null:
		rim_height_style = _build_preset(height_preset)


static func _build_preset(preset: HeightPreset) -> Curve:
	var curve := Curve.new()
	# Without this, an @tool _ready() build like this one gets its result
	# baked as the scene's *default* value by an editor save pass — and an
	# un-local-to-scene default Resource is shared by reference across every
	# instance of ring_wall.tscn (the 4 stacked rings in the composite all
	# pointed at the same Curve until this was set). See
	# .claude/rules/godot-workflow.md for the sibling gotcha (editor passes
	# silently mutating hand-authored .tscn/.tres state).
	curve.resource_local_to_scene = true
	match preset:
		HeightPreset.LEVEL:
			curve.add_point(Vector2(0.0, 0.0))
			curve.add_point(Vector2(1.0, 1.0))
		HeightPreset.TERRACE:
			curve.add_point(Vector2(0.0, 0.0))
			curve.add_point(Vector2(0.33, 0.33))
			curve.add_point(Vector2(0.34, 0.66))
			curve.add_point(Vector2(0.67, 0.66))
			curve.add_point(Vector2(0.68, 1.0))
			curve.add_point(Vector2(1.0, 1.0))
		HeightPreset.SMOOTH:
			curve.add_point(Vector2(0.0, 0.0))
			curve.add_point(Vector2(0.25, 0.1))
			curve.add_point(Vector2(0.5, 0.5))
			curve.add_point(Vector2(0.75, 0.9))
			curve.add_point(Vector2(1.0, 1.0))
		HeightPreset.SHARPEN:
			curve.add_point(Vector2(0.0, 0.0))
			curve.add_point(Vector2(0.6, 0.15))
			curve.add_point(Vector2(1.0, 1.0))
	return curve


func _sample_height(t: float) -> float:
	if rim_height_style == null:
		return t
	return clampf(rim_height_style.sample(clampf(t, 0.0, 1.0)), 0.0, 1.0)


func _draw() -> void:
	var span := geom_rim_r - geom_crest_r
	if span <= 0.0:
		return
	for i in RING_STEPS:
		var t0 := float(i) / RING_STEPS
		var t1 := float(i + 1) / RING_STEPS
		var r0 := lerpf(geom_crest_r, geom_rim_r, t0)
		var r1 := lerpf(geom_crest_r, geom_rim_r, t1)
		var h := _sample_height((t0 + t1) * 0.5)
		var shade := 0.35 + 0.65 * h
		var band_color := Color(wall_color.r * shade, wall_color.g * shade, wall_color.b * shade, wall_color.a)
		var width := r1 - r0
		draw_circle(Vector2.ZERO, (r0 + r1) * 0.5, band_color, false, width + 0.5, true)
