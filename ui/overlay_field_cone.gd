class_name OverlayFieldCone
extends RefCounted

## CPU reference for the overlay field's **rounded-cone** primitive — the GLSL
## twin lives in `ui/overlay_field.gdshaderinc` (`field_cone_distance` /
## `field_cone_project`) and must stay line-for-line equivalent.
##
## A cone is two endpoints `a`, `b` with radii `ra`, `rb`. Its NORMALIZED
## distance is
## [codeblock]
## d(p) = min over t in [0,1] of |p - c(t)| / r(t),  c = lerp(a,b,t), r = lerp(ra,rb,t)
## [/codeblock]
## i.e. the factor the whole configuration must be scaled by for `p` to land on
## the hull of the two discs. That makes `d == 1` the hull boundary, `d < 1` the
## interior, and — crucially — it reduces to the plain disc distance
## `|p - a| / ra` at each end, so the existing `falloff` / `smoothstep` fade and
## `field_smin` union apply to cones exactly as they do to circles.
##
## Degenerate cases fall out for free: `a == b` is a disc, `ra == rb` is a
## capsule (perpendicular distance / r).
##
## See docs/domain/overlay-field-rendering.md and #897.

## Stub — see #897 acceptance 1.
static func distance(p: Vector2, a: Vector2, ra: float, b: Vector2, rb: float) -> float:
	return 0.0


## Clamped orthogonal projection of `p` onto the segment `a`→`b`. This is the
## point the tile index buckets for dedupe — NOT the argmin `t*` of
## [method distance].
static func project(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ba := b - a
	var l2 := ba.dot(ba)
	if l2 <= 0.0:
		return a
	var t := clampf((p - a).dot(ba) / l2, 0.0, 1.0)
	return a + ba * t
