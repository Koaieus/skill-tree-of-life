@tool
extends SkillNodeRingVisual
## STUB — fleshed out by #125 (single structural wall ring, height(radius)
## profile between crest and rim).

const STUB_COLOR := Color(0.7, 0.7, 0.7, 0.9)


func _draw() -> void:
	draw_ring_band(-6.0, 6.0, STUB_COLOR)
	draw_string(ThemeDB.fallback_font, Vector2(-radius, radius + 14.0), "ring_wall", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12, STUB_COLOR)
