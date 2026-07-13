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
@export var stroke_color: Color = Color(1, 1, 1, 0.9)
@export var fill_color: Color = Color(1, 1, 1, 0.12)
@export var stroke_width: float = 2.0


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
	if sigil.closed:
		draw_colored_polygon(pts, fill_color)
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, stroke_color, stroke_width, true)
	else:
		draw_polyline(pts, stroke_color, stroke_width, true)
