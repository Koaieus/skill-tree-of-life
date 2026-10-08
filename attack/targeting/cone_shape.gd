@tool
class_name ConeShape
extends AimShape

## A wedge of [member half_angle_deg] either side of the aim, out to the
## length. A node is crossed when its disc is within reach
## ([method EuclideanRangeFinder._reaches]) and any part of it lies inside the
## wedge — its centre's angular offset less the angle its disc subtends.

## Half the wedge's opening. Tentative.
@export_range(1.0, 90.0, 0.5, "suffix:°") var half_angle_deg: float = 20.0


func _touches(origin: Vector2, dir: Vector2, length: float, node: SkillNode) -> bool:
	var rel := node.global_position - origin
	var d := rel.length()
	if not EuclideanRangeFinder._reaches(d, node, length):
		return false
	# A disc that contains the origin covers every heading; asin would also be
	# out of its domain here.
	if d <= node.radius:
		return true
	var offset := absf(dir.angle_to(rel)) - asin(node.radius / d)
	return offset <= deg_to_rad(half_angle_deg)
