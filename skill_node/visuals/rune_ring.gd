@tool
extends SkillNodeRingVisual
## STUB — fleshed out by #129 (1-3 spinning concentric rune-glyph bands,
## auto-clearing the node's current actual outer edge).

const STUB_COLOR := Color(0.69, 0.40, 0.97, 0.9)


func _draw() -> void:
	var r := radius * 1.5
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, STUB_COLOR, 1.5, true)
	draw_string(ThemeDB.fallback_font, Vector2(-radius, r + 14.0), "rune_ring", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12, STUB_COLOR)
