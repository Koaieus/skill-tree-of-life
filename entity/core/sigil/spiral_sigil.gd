@tool
class_name SpiralSigil
extends Sigil

## An Archimedean spiral winding inward from the rim — the Serpent's coil,
## the same shape its constellation is rewarded for building. Open path:
## drawn as a stroked polyline, never filled.

@export_range(1.0, 6.0, 0.5) var turns: float = 2.5
@export_range(8, 256, 1) var samples: int = 96


func _init() -> void:
	closed = false


func points(radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in samples:
		var t := float(i) / float(samples - 1)
		var angle := t * turns * TAU
		var r := radius * (1.0 - t)
		out.append(Vector2(cos(angle), sin(angle)) * r)
	return out
