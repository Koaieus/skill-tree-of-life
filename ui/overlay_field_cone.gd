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

## Normalized distance from `p` to the rounded cone `(a, ra)`→`(b, rb)`.
##
## [b]Derivation.[/b] Minimizing `h(t) = |pa - t*ba| / (ra + t*rd)` (with
## `pa = p - a`, `ba = b - a`, `rd = rb - ra`) over `t`: setting `h'(t) = 0`
## clears to `N'(t)*D(t) = 2*N(t)*rd`, whose `t²` terms cancel, leaving a
## [i]linear[/i] equation — one closed-form stationary point
## [codeblock]
## t* = (rd*Q + ra*P) / (L2*ra + rd*P),   P = pa·ba, Q = pa·pa, L2 = ba·ba
## [/codeblock]
##
## [b]Why the min against both endpoints is load-bearing, not defensive.[/b]
## `h` has a pole at `t = -ra/rd`, and `t*` can land on the [i]far side[/i] of
## it — the nested case, one disc inside the other. `a=(0,0) ra=10`,
## `b=(5,0) rb=1`, `p=(20,0)` gives `t* = 4`, which clamps to `1` and reports
## `15` where the true minimum is `h(0) = 2`. `t*` also sweeps through ±INF as
## the denominator crosses zero, which would make `d` discontinuous. Because
## `h` is unimodal on the branch containing `[0,1]`, taking
## `min(h(0), h(1), h(clamp(t*)))` is exactly the minimum whenever `t*` is
## meaningful and is still correct when it is not.
##
## `L2 == 0` (a disc) and a vanishing denominator both take `t = 0` — note
## `0/0` is NaN and `clamp(NaN)` is undefined in GLSL, so the guard is
## required in the twin, not merely tidy.
static func distance(p: Vector2, a: Vector2, ra: float, b: Vector2, rb: float) -> float:
	var pa := p - a
	var ba := b - a
	var rd := rb - ra
	var l2 := ba.dot(ba)
	var pp := pa.dot(ba)
	var den := l2 * ra + rd * pp
	var t := 0.0
	if l2 > 0.0 and absf(den) > 1e-8:
		t = clampf((rd * pa.dot(pa) + ra * pp) / den, 0.0, 1.0)
	var d := minf(pa.length() / ra, (p - b).length() / rb)
	return minf(d, (pa - ba * t).length() / (ra + rd * t))


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
