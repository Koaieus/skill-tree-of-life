@tool
class_name AstroidSigil
extends Sigil

## The four-cusped hypocycloid: x = r·cos³t, y = r·sin³t. Balanced's mark —
## symmetric in every direction, no axis favored, nothing sharp. Replaces the
## "✦" glyph [HeroSigilCard] stood in with for every class before #39.

# Editor preview, editor-composing, and the .gd-vs-.tres question for concrete
# sigils are tracked in #167 (Sigil ↔ inner-disk weld unification / rendering).

@export_range(8, 128, 1) var samples: int = 64


func points(radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in samples:
		var t := TAU * float(i) / float(samples)
		var c := cos(t)
		var s := sin(t)
		out.append(Vector2(c * c * c, s * s * s) * radius)
	return out
