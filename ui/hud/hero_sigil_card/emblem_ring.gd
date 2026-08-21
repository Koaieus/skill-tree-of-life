@tool
class_name EmblemRing
extends Control
## Conic-gradient-look ring for the Hero Sigil Card's class emblem. No conic
## fill exists on [GradientTexture2D] in Godot 4, so this draws N arc wedges
## with alpha ramping around the sweep — cheaper than a shader and just as
## rotatable (the parent [HeroSigilCard] spins the whole node every frame).

## Authored fallback hue, in plain LDR sRGB. [method _draw] lifts it to the
## VALUE tier itself (#390 — a thin ring needs the full stop to read at all,
## `docs/domain/hdr-color.md`: coverage is half the effect). The lift lives in
## `_draw` and NOT in this default on purpose: a computed default is a derived
## value, and the editor bakes those back into the `.tscn` to be re-lifted on
## the next load (`.claude/rules/gdscript-pitfalls.md`).
@export var ring_color: Color = Color(0.9, 0.75, 0.4):
	set(v):
		ring_color = v
		queue_redraw()

## Identity colour of whoever is bound — the ring is the hero's emblem, so it
## carries ownership, exactly as [SkillNodeVisual]'s `entity_tint` does on the
## board. Written at runtime by [method HeroSigilCard.bind] from
## [member Entity.color]; a plain var rather than an `@export` because it is
## runtime identity, not authored content. Alpha 0 means "nobody bound" and
## the ring falls back to [member ring_color].
var entity_tint: Color = Color(0, 0, 0, 0):
	set(v):
		entity_tint = v
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

## The hue actually drawn: the bound identity when there is one, else the
## authored fallback — lifted to the VALUE tier here rather than stored.
## `tint`, not `tint_peak`: a 4px stroke is the thin-mark case (see Emissive).
func _lit_color() -> Color:
	var base := entity_tint if entity_tint.a > 0.0 else ring_color
	return Emissive.tint(base, Emissive.VALUE)


func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - ring_width * 0.5
	if radius <= 0.0:
		return
	var lit := _lit_color()
	for i in segment_count:
		var t0 := float(i) / float(segment_count)
		var t1 := float(i + 1) / float(segment_count)
		var alpha := lit.a * t0
		var col := Color(lit.r, lit.g, lit.b, alpha)
		draw_arc(center, radius, t0 * TAU, t1 * TAU, 2, col, ring_width, true)
