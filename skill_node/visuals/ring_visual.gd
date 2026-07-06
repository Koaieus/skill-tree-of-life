@tool
class_name SkillNodeRingVisual
extends SkillNodeVisual
## Base class for ring-shaped components (rim wall, rim bonuses, core halos,
## rune ring, ...). `ring_centerline()` delegates to the existing
## `SkillNode.ring_centerline` static rather than re-deriving the arithmetic —
## one formula, per .claude/rules/skill-node-visuals.md.

@export var inner_radius: float = 24.0:
	set(value):
		inner_radius = value
		queue_redraw()

@export var outer_radius: float = 32.0:
	set(value):
		outer_radius = value
		queue_redraw()


## Stroke centerline for a ring specified as (inner_offset, width) relative to
## `radius` — see .claude/rules/skill-node-visuals.md for the convention.
func ring_centerline(inner_offset: float, width: float) -> float:
	return SkillNode.ring_centerline(radius, inner_offset, width)


## Convenience: stroke a ring band at (inner_offset, width) relative to radius.
func draw_ring_band(inner_offset: float, width: float, color: Color) -> void:
	draw_circle(Vector2.ZERO, ring_centerline(inner_offset, width), color, false, width, true)
