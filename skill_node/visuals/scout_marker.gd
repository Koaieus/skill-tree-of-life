class_name ScoutMarker
extends Node2D

## The face of a scouted mark (#1033): a thin ring just outside the node's
## rim in [member def]'s tint, with its icon (if authored) centred above.
## Instanced lazily by [SkillNode] on the node's first mark, so an unscouted
## node — the common case — carries nothing. Plain `_draw`, no material: a
## per-node material would break the node batch (`.claude/rules/rendering-performance.md`).

## The status that owns the look — authored on the scene so face and rules
## are both data; [VisionSystem.scouted_def] is the same def's other door.
@export var def: StatusDef
@export var ring_gap: float = 5.0
@export var ring_width: float = 2.0

var ring_radius: float = 0.0:
	set(value):
		ring_radius = value
		queue_redraw()


func _draw() -> void:
	var tint: Color = def.tint if def != null else Color.WHITE
	draw_arc(Vector2.ZERO, ring_radius + ring_gap, 0.0, TAU, 48, tint, ring_width, true)
	var icon: Texture2D = def.icon if def != null else null
	if icon != null:
		var size: Vector2 = icon.get_size()
		draw_texture_rect(icon,
				Rect2(Vector2(-size.x * 0.5, -(ring_radius + ring_gap + size.y + 2.0)), size),
				false, tint)
