@tool
class_name BadgeFrame
extends Resource

## One [Identity.Kind]'s badge frame: a regular polygon of [member sides]
## vertices, turned by [member rotation_deg] (0 puts a vertex on +x, so a
## hexagon reads flat-top). Many sides read as a circle.

@export_range(3, 64) var sides: int = 6:
	set(value):
		sides = maxi(3, value)
		emit_changed()
@export_range(-180.0, 180.0, 0.5) var rotation_deg: float = 0.0:
	set(value):
		rotation_deg = value
		emit_changed()


## The polygon's vertices around `center` at circumradius `radius`, in
## canvas/image space (y down), starting at [member rotation_deg].
func vertices(center: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var start := deg_to_rad(rotation_deg)
	for i in sides:
		out.append(center + Vector2.from_angle(start + TAU * i / sides) * radius)
	return out
