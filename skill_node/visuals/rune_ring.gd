@tool
extends SkillNodeVisual
## Rune ring (#129): 1-3 spinning concentric rune-glyph bands, auto-clearing
## the node's CURRENT actual outer edge — [member outer_edge_r] is fed by
## the composite as stake rings grow it; a standalone preview falls back to
## [member radius] so gap/spacing are always measured from the real
## boundary, never a fixed one.

## The bands read the archetype identity (see [SkillNodeVisual]) — a rune ring
## is structure, not ownership. Its ink/glyph colors below are private and
## deliberately identity-free.
enum RuneCount { NONE, SINGLE, DOUBLE, TRIPLE }
enum RuneStyle { FLUSH, ORNATE, MIXED }
enum RuneBlend { CUTOUT, INK, GLOW }

const RUNES_PER_BAND := 8

@export var band_count: RuneCount = RuneCount.NONE:
	set(value):
		band_count = value
		set_animating(band_count != RuneCount.NONE)
		queue_redraw()
## flush/ornate/mixed — band width + rune scale preset.
@export var style: RuneStyle = RuneStyle.FLUSH:
	set(value):
		style = value
		queue_redraw()
@export var blend: RuneBlend = RuneBlend.INK:
	set(value):
		blend = value
		queue_redraw()
## Shared inner+outer edge glow.
@export_range(0.0, 1.0, 0.01) var edge_glow: float = 0.3:
	set(value):
		edge_glow = value
		queue_redraw()
## Band's own opaque core strength.
@export_range(0.0, 1.0, 0.01) var fill_amount: float = 0.85:
	set(value):
		fill_amount = value
		queue_redraw()
## Glyph-specific glow/blur, independent of edge_glow.
@export_range(0.0, 1.0, 0.01) var glyph_glow: float = 0.0:
	set(value):
		glyph_glow = value
		queue_redraw()
## Shrinks glyphs off the inner/outer edge.
@export_range(0.0, 1.0, 0.01) var glyph_pad: float = 0.2:
	set(value):
		glyph_pad = value
		queue_redraw()
## Radial offset from the node's current actual outer edge.
@export_range(0.0, 32.0, 0.5) var gap: float = 6.0:
	set(value):
		gap = value
		queue_redraw()
@export_range(0.0, 32.0, 0.5) var spacing: float = 8.0:
	set(value):
		spacing = value
		queue_redraw()

## Node's current actual outer edge (post stake-growth). 0 -> fall back to
## [member radius] (standalone preview / not yet wired by a composite).
@export_range(0.0, 128.0, 0.5) var outer_edge_r: float = 0.0:
	set(value):
		outer_edge_r = value
		queue_redraw()


func _band_count() -> int:
	match band_count:
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
	match style:
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
	var start_r := edge + gap
	for b in count:
		var r := start_r + b * (band_width + spacing)
		var spin_dir := 1.0 if b % 2 == 0 else -1.0
		var rotation := anim_time * (0.4 + b * 0.25) * spin_dir
		_draw_band(r, band_width, rune_scale, rotation)


func _draw_band(r: float, width: float, rune_scale: float, rotation: float) -> void:
	var fill_color := Color(archetype_tint, fill_amount)
	var rune_len := width * (1.0 - glyph_pad) * rune_scale

	if edge_glow > 0.0:
		draw_circle(Vector2.ZERO, r, Color(archetype_tint, edge_glow * 0.3), false, width * 1.6, true)

	if blend == RuneBlend.CUTOUT:
		_draw_cutout_band(r, width, rune_len, rotation, fill_color)
		return

	draw_circle(Vector2.ZERO, r, fill_color, false, width, true)
	var rune_color := Color(0.05, 0.05, 0.08, 0.9) if blend == RuneBlend.INK else Color(1.0, 1.0, 1.0, 0.9)
	for i in RUNES_PER_BAND:
		var theta := rotation + (TAU / RUNES_PER_BAND) * i
		var p0 := polar_point(r - rune_len * 0.5, theta)
		var p1 := polar_point(r + rune_len * 0.5, theta)
		draw_line(p0, p1, rune_color, 2.0, true)
		if glyph_glow > 0.0 and blend == RuneBlend.GLOW:
			draw_line(p0, p1, Color(1, 1, 1, glyph_glow * 0.4), 5.0, true)


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
