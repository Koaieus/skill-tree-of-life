@tool
extends SkillNodeVisual
## STUB — fleshed out by #123 (semi-sphere canvas_item shader inner disk).
## Placeholder draws a flat wash + outline so the slot isn't blank in the
## sandbox panel until the real shader lands.

const STUB_COLOR := Color(0.291, 0.5892, 1.0, 0.9)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(STUB_COLOR.r, STUB_COLOR.g, STUB_COLOR.b, 0.15))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, STUB_COLOR, 2.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(-radius, radius + 14.0), "inner_disk", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12, STUB_COLOR)
