@tool
class_name CircleSigil
extends Sigil

## A plain circle — no points, no notches, no fold symmetry at all. Pacifist's
## mark: stillness itself, the shape every other sigil is spiky or coiled
## against. The low-alpha fill every [Sigil] shares (see [SigilGlyph]) reads
## this one as a thin ring, not a solid disc.

@export_range(8, 128, 1) var samples: int = 64


func points(radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in samples:
		var t := TAU * float(i) / float(samples)
		out.append(Vector2(cos(t), sin(t)) * radius)
	return out
