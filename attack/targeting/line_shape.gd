@tool
class_name LineShape
extends AimShape

## A straight band from the origin out to the length: a node is crossed when
## its disc comes within [member width] of the segment — a capsule test, so a
## disc just past the segment's far end still clips the rounded cap.

## Half-width of the band, added to each node's disc radius. Tentative.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:px") var width: float = 24.0


func _touches(origin: Vector2, dir: Vector2, length: float, node: SkillNode) -> bool:
	var rel := node.global_position - origin
	var along := clampf(rel.dot(dir), 0.0, length)
	return rel.distance_to(dir * along) - node.radius <= width
