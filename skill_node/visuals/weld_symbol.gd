@tool
extends SkillNodeVisual
## STUB — fleshed out by #124 (glyph overlay with shader blending).
## Placeholder draws a square outline so the slot isn't blank until the real
## per-archetype glyph + blend material lands.

const STUB_COLOR := Color(1.0, 0.85, 0.3, 0.9)


func _draw() -> void:
	var s := radius * 0.6
	draw_rect(Rect2(Vector2(-s, -s), Vector2(s, s) * 2.0), STUB_COLOR, false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(-radius, radius + 14.0), "weld_symbol", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12, STUB_COLOR)
