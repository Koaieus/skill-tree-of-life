@tool
class_name StarSigil
extends Sigil

## An N-pointed star: sharp outer spikes alternating with an inner waist.
## The Ninja's mark — a thrown blade, not a smooth curve. Default 4 points
## reads as a shuriken.

@export_range(3, 12, 1) var point_count: int = 4
## Inner radius as a fraction of the outer radius. Lower = sharper spikes.
@export_range(0.05, 0.95, 0.01) var inner_ratio: float = 0.35


func points(radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var total := point_count * 2
	for i in total:
		var t := TAU * float(i) / float(total) - PI / 2.0
		var r := radius if i % 2 == 0 else radius * inner_ratio
		out.append(Vector2(cos(t), sin(t)) * r)
	return out
