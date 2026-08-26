@tool
class_name TriangleSigil
extends Sigil

## A plain three-sided spike, point up — no curvature, no coil, nothing past
## the minimum a closed shape needs. Basic Enemy's mark: the simplest
## possible threat, no flourish, just a point aimed at you.


func points(radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 3:
		var t := TAU * float(i) / 3.0 - PI / 2.0
		out.append(Vector2(cos(t), sin(t)) * radius)
	return out
