@tool
class_name EmblemRing
extends Control
## Conic-gradient-look ring for the Hero Sigil Card's class emblem. No conic
## fill exists on [GradientTexture2D] in Godot 4, so this draws N arc wedges
## with alpha ramping around the sweep — cheaper than a shader and just as
## rotatable (the parent [HeroSigilCard] spins the whole node every frame).

## VALUE tier (#390) — a thin ring needs the full stop to read at all
## (`docs/domain/hdr-color.md`: coverage is half the effect).
@export var ring_color: Color = Emissive.at(Color(0.9, 0.75, 0.4), Emissive.VALUE):
	set(v):
		ring_color = v
		queue_redraw()

@export_range(2.0, 20.0, 0.5) var ring_width: float = 4.0:
	set(v):
		ring_width = v
		queue_redraw()

@export_range(8, 128, 1) var segment_count: int = 48:
	set(v):
		segment_count = v
		queue_redraw()

func _ready() -> void:
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)

func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - ring_width * 0.5
	if radius <= 0.0:
		return
	for i in segment_count:
		var t0 := float(i) / float(segment_count)
		var t1 := float(i + 1) / float(segment_count)
		var alpha := ring_color.a * t0
		var col := Color(ring_color.r, ring_color.g, ring_color.b, alpha)
		draw_arc(center, radius, t0 * TAU, t1 * TAU, 2, col, ring_width, true)
