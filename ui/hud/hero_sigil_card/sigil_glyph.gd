@tool
class_name SigilGlyph
extends Control

## Draws a [Sigil]'s outline, centered and scaled to fit this control.
## Sibling to `EmblemGlyph` (the `"✦"` fallback [Label]) inside
## [HeroSigilCard]'s Portrait — the card shows whichever one has content.

@export var sigil: Sigil = null:
	set(v):
		sigil = v
		queue_redraw()
## Authored fallbacks. Their ALPHAs are the real authored content — stroke and
## fill differ only in weight — so [member entity_tint] replaces the hue and
## leaves both alphas alone.
@export var stroke_color: Color = Color(1, 1, 1, 0.9)
@export var fill_color: Color = Color(1, 1, 1, 0.12)
@export var stroke_width: float = 2.0

## Identity colour of whoever is bound, written at runtime by
## [method HeroSigilCard.bind] — same contract as [member EmblemRing.entity_tint]
## (plain var, alpha 0 means "nobody bound").
var entity_tint: Color = Color(0, 0, 0, 0):
	set(v):
		entity_tint = v
		queue_redraw()


## Recolour an authored swatch to the bound identity, keeping its alpha.
func _tinted(authored: Color) -> Color:
	if entity_tint.a <= 0.0:
		return authored
	return Color(entity_tint.r, entity_tint.g, entity_tint.b, authored.a)


func _draw() -> void:
	if sigil == null:
		return
	var radius := minf(size.x, size.y) * 0.5 * 0.8
	var center := size * 0.5
	var raw := sigil.points(radius)
	if raw.is_empty():
		return
	var pts := PackedVector2Array()
	for p in raw:
		pts.append(p + center)
	var stroke := _tinted(stroke_color)
	if sigil.closed:
		draw_colored_polygon(pts, _tinted(fill_color))
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, stroke, stroke_width, true)
	else:
		draw_polyline(pts, stroke, stroke_width, true)
