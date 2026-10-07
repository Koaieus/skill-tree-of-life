@tool
extends ArrowImpactSprite

## The hex arrow's mark: an eye-sigil that blinks open over the node, then
## fades — "you're marked". The kit sprite draws a texture or a ring; an eye
## is neither, so this overrides only [method _draw]. Lifetime, anchor, tint,
## tier and the fade stay the part's: [member scale_curve] is the lid opening
## (0 shut, 1 wide), [member alpha_curve] the fade, [member size] the
## half-width of the eye.

## Lid height at full opening, as a fraction of [member size].
@export_range(0.1, 1.0, 0.01) var lid_ratio: float = 0.55:
	set(v):
		lid_ratio = v
		queue_redraw()
## Pupil radius, as a fraction of [member size]; hidden while the lids are
## narrower than it.
@export_range(0.05, 0.6, 0.01) var pupil_ratio: float = 0.22:
	set(v):
		pupil_ratio = v
		queue_redraw()
## Points per lid curve.
@export_range(4, 32) var lid_segments: int = 12:
	set(v):
		lid_segments = v
		queue_redraw()


func _draw() -> void:
	if _t < 0.0 or _tint.a <= 0.0:
		return
	var k := clampf(_t, 0.0, 1.0)
	var open := clampf(scale_curve.sample(k) if scale_curve != null else 1.0, 0.0, 1.0)
	var a := alpha_curve.sample(k) if alpha_curve != null else 1.0 - k
	var col := ArrowPart.lit(_tint, tier)
	col.a = a
	var lid := size * lid_ratio * open
	var outline := PackedVector2Array()
	for i in lid_segments + 1:
		outline.append(_lid_point(float(i) / lid_segments, -lid))
	for i in range(lid_segments - 1, -1, -1):
		outline.append(_lid_point(float(i) / lid_segments, lid))
	draw_polyline(outline, col, ring_width, true)
	var pupil := size * pupil_ratio
	if lid > pupil * 0.5:
		draw_circle(Vector2.ZERO, minf(pupil, lid), col, true, -1.0, true)


## A point on a quadratic lid from the left corner to the right; [param bulge]
## is the peak offset at the middle (negative = upper lid).
func _lid_point(u: float, bulge: float) -> Vector2:
	return Vector2(lerpf(-size, size, u), bulge * 4.0 * u * (1.0 - u))
