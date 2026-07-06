@tool
extends SkillNodeRingVisual
## Rune ring (#129): 1-3 spinning concentric rune-glyph bands, auto-clearing
## the node's CURRENT actual outer edge — [member outer_edge_r] is fed by
## the composite as stake rings grow it; a standalone preview falls back to
## [member radius] so gap/spacing are always measured from the real
## boundary, never a fixed one.

enum RuneCount { NONE, SINGLE, DOUBLE, TRIPLE }
enum RuneStyle { FLUSH, ORNATE, MIXED }
enum RuneBlend { CUTOUT, INK, GLOW }

const BAND_COLOR := Color(0.55, 0.35, 0.85)
const RUNES_PER_BAND := 8

@export var rune_ring: RuneCount = RuneCount.NONE:
	set(value):
		rune_ring = value
		set_process(rune_ring != RuneCount.NONE)
		queue_redraw()
## flush/ornate/mixed — band width + rune scale preset.
@export var rune_ring_style: RuneStyle = RuneStyle.FLUSH:
	set(value):
		rune_ring_style = value
		queue_redraw()
@export var rune_ring_blend: RuneBlend = RuneBlend.INK:
	set(value):
		rune_ring_blend = value
		queue_redraw()
## Shared inner+outer edge glow.
@export_range(0.0, 1.0, 0.01) var rune_ring_glow: float = 0.3:
	set(value):
		rune_ring_glow = value
		queue_redraw()
## Band's own opaque core strength.
@export_range(0.0, 1.0, 0.01) var rune_ring_fill: float = 0.85:
	set(value):
		rune_ring_fill = value
		queue_redraw()
## Glyph-specific glow/blur, independent of rune_ring_glow.
@export_range(0.0, 1.0, 0.01) var rune_ring_rune_glow: float = 0.0:
	set(value):
		rune_ring_rune_glow = value
		queue_redraw()
## Shrinks glyphs off the inner/outer edge.
@export_range(0.0, 1.0, 0.01) var rune_ring_pad: float = 0.2:
	set(value):
		rune_ring_pad = value
		queue_redraw()
## Radial offset from the node's current actual outer edge.
@export var rune_ring_gap: float = 6.0:
	set(value):
		rune_ring_gap = value
		queue_redraw()
@export var rune_ring_spacing: float = 8.0:
	set(value):
		rune_ring_spacing = value
		queue_redraw()

## Node's current actual outer edge (post stake-growth). 0 -> fall back to
## [member radius] (standalone preview / not yet wired by a composite).
@export var outer_edge_r: float = 0.0:
	set(value):
		outer_edge_r = value
		queue_redraw()

var _t: float = 0.0


func _ready() -> void:
	set_process(rune_ring != RuneCount.NONE)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _band_count() -> int:
	match rune_ring:
		RuneCount.SINGLE:
			return 1
		RuneCount.DOUBLE:
			return 2
		RuneCount.TRIPLE:
			return 3
		_:
			return 0


## (band_width, rune_scale) per style.
func _style_widths() -> Vector2:
	match rune_ring_style:
		RuneStyle.FLUSH:
			return Vector2(4.0, 0.8)
		RuneStyle.ORNATE:
			return Vector2(8.0, 1.2)
		_:
			return Vector2(6.0, 1.0)  # MIXED


func _draw() -> void:
	var count := _band_count()
	if count <= 0:
		return
	var edge := outer_edge_r if outer_edge_r > 0.0 else radius
	var widths := _style_widths()
	var band_width: float = widths.x
	var rune_scale: float = widths.y
	var start_r := edge + rune_ring_gap
	for b in count:
		var r := start_r + b * (band_width + rune_ring_spacing)
		var spin_dir := 1.0 if b % 2 == 0 else -1.0
		var rotation := _t * (0.4 + b * 0.25) * spin_dir
		_draw_band(r, band_width, rune_scale, rotation)


func _draw_band(r: float, width: float, rune_scale: float, rotation: float) -> void:
	var fill_color := Color(BAND_COLOR.r, BAND_COLOR.g, BAND_COLOR.b, rune_ring_fill)
	var rune_len := width * (1.0 - rune_ring_pad) * rune_scale

	if rune_ring_glow > 0.0:
		draw_circle(Vector2.ZERO, r, Color(BAND_COLOR.r, BAND_COLOR.g, BAND_COLOR.b, rune_ring_glow * 0.3), false, width * 1.6, true)

	if rune_ring_blend == RuneBlend.CUTOUT:
		_draw_cutout_band(r, width, rune_len, rotation, fill_color)
		return

	draw_circle(Vector2.ZERO, r, fill_color, false, width, true)
	var rune_color := Color(0.05, 0.05, 0.08, 0.9) if rune_ring_blend == RuneBlend.INK else Color(1.0, 1.0, 1.0, 0.9)
	for i in RUNES_PER_BAND:
		var theta := rotation + (TAU / RUNES_PER_BAND) * i
		var p0 := polar_point(r - rune_len * 0.5, theta)
		var p1 := polar_point(r + rune_len * 0.5, theta)
		draw_line(p0, p1, rune_color, 2.0, true)
		if rune_ring_rune_glow > 0.0 and rune_ring_blend == RuneBlend.GLOW:
			draw_line(p0, p1, Color(1, 1, 1, rune_ring_rune_glow * 0.4), 5.0, true)


## Solid band with each rune position punched to true alpha 0 — drawn as
## separate arcs spanning the gaps BETWEEN rune slots, so the scene/glow
## behind the node shows through at the rune positions themselves.
func _draw_cutout_band(r: float, width: float, rune_len: float, rotation: float, fill_color: Color) -> void:
	var step := TAU / RUNES_PER_BAND
	var half_angle: float = clampf(rune_len / maxf(r, 1.0) * 0.5, 0.01, step * 0.45)
	for i in RUNES_PER_BAND:
		var theta := rotation + step * i
		var solid_start := theta + half_angle
		var solid_end := rotation + step * (i + 1) - half_angle
		if solid_end > solid_start:
			draw_arc(Vector2.ZERO, r, solid_start, solid_end, 6, fill_color, width, true)
