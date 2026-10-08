@tool
class_name ConeShape
extends AimShape

## A wedge of [member half_angle_deg] either side of the aim, out to the
## length. A node is crossed when its disc is within reach
## ([method EuclideanRangeFinder._reaches]) and any part of it lies inside the
## wedge (its centre inside, or its disc across an edge).

## Half the wedge's opening. Tentative.
@export_range(1.0, 90.0, 0.5, "suffix:°") var half_angle_deg: float = 20.0


func _touches(origin: Vector2, dir: Vector2, length: float, node: SkillNode) -> bool:
	var rel := node.global_position - origin
	var d := rel.length()
	if not EuclideanRangeFinder._reaches(d, node, length):
		return false
	# A disc that contains the origin covers every heading.
	if d <= node.radius:
		return true
	# The centre lies inside the wedge, or the disc reaches across one of its
	# two edges. The one trig step is `from_angle` of the authored knob, as
	# [method AimShape.crossed] takes `from_angle` of the aim: the crossed set
	# rides the AttackRecord, so a peer receives it rather than recomputing it.
	var edge := Vector2.from_angle(deg_to_rad(half_angle_deg))
	if rel.dot(dir) >= d * edge.x:
		return true
	for side: float in [1.0, -1.0]:
		var ray := Vector2(dir.x * edge.x - dir.y * edge.y * side, dir.y * edge.x + dir.x * edge.y * side)
		if rel.distance_to(ray * maxf(0.0, rel.dot(ray))) <= node.radius:
			return true
	return false
