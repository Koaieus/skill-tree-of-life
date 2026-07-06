@tool
extends SkillNodeRingVisual
## STUB — fleshed out by #127 (rimTone tinted gems + rimHolder neutral
## chrome, independent composable layers on/around the rim).

const STUB_COLOR := Color(0.94, 0.27, 0.25, 0.9)


func _draw() -> void:
	draw_ring_band(2.0, 3.0, STUB_COLOR)
	draw_string(ThemeDB.fallback_font, Vector2(-radius, radius + 14.0), "rim_bonuses", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12, STUB_COLOR)
