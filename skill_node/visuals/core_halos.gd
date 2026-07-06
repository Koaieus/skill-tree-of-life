@tool
extends SkillNodeRingVisual
## STUB — fleshed out by #128 (rings/orbit/gimbal/cog nucleus-presence
## halos, spinning outside the rim). Spikes are explicitly excluded — that
## register belongs to the addons system.

const STUB_COLOR := Color(0.32, 0.78, 0.45, 0.9)


func _draw() -> void:
	var r := radius * 1.3
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, STUB_COLOR, 1.5, true)
	draw_string(ThemeDB.fallback_font, Vector2(-radius, r + 14.0), "core_halos", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 12, STUB_COLOR)
