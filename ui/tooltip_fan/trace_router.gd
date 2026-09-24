## Tooltip V2 (#159 Phase 0) — pure geometry helper for fan-trace connectors.
##
## Decoupled from any fan orientation, layout, or node: given two points and a
## style, returns the polyline a trace line should follow. No randomness, no
## node dependencies — callers own how the points get drawn (Line2D, etc.).
class_name TraceRouter
extends RefCounted

enum Style { STRAIGHT, ELBOW, TREE, PCB }


## Returns the ordered points of the trace from `from` to `to` for `style`.
## `first == from` and `last == to` always hold, for every style.
static func compute_trace_points(from: Vector2, to: Vector2, style: int, params: Dictionary) -> PackedVector2Array:
	match style:
		Style.STRAIGHT:
			return _straight(from, to)
		Style.ELBOW:
			return _elbow(from, to, params)
		Style.TREE:
			return _tree(from, to, params)
		Style.PCB:
			return _pcb(from, to, params)
		_:
			return _straight(from, to)


static func _straight(from: Vector2, to: Vector2) -> PackedVector2Array:
	return PackedVector2Array([from, to])


## One right-angle-capable corner. The dominant axis (the one with the larger
## absolute delta) decides the corner's orientation; `params.corner` (default
## 0.5) is the fraction along that dominant axis where the bend sits.
##
## The leg from `from` to the corner is always exactly axis-aligned (purely
## along the dominant axis). The closing leg (corner -> to) is a true
## perpendicular (right-angle) run only at corner == 1.0 — the canonical
## squared elbow; smaller fractions pull the bend earlier and the closing leg
## becomes a direct (non-orthogonal) run into `to`. This mirrors TREE's
## diagonal(0)/squared-corner(1) `bend` knob by design.
static func _elbow(from: Vector2, to: Vector2, params: Dictionary) -> PackedVector2Array:
	var corner: float = params.get("corner", 0.5)
	var dx := to.x - from.x
	var dy := to.y - from.y
	var corner_point: Vector2
	if absf(dx) >= absf(dy):
		corner_point = Vector2(lerpf(from.x, to.x, corner), from.y)
	else:
		corner_point = Vector2(from.x, lerpf(from.y, to.y, corner))
	return PackedVector2Array([from, corner_point, to])


## A vertical trunk sprouting from `from` upward (negative Y) by
## `params.sprout` (default 24.0), then a shaped route into `to`.
## `params.bend` (default 0.5) blends the route from a point sitting on the
## direct diagonal (0.0 — looks like a straight descent) to the fully squared
## right-angle corner (1.0 — horizontal from the trunk top, then vertical into
## `to`). Always 4 deterministic points: [from, trunk_top, route_point, to].
static func _tree(from: Vector2, to: Vector2, params: Dictionary) -> PackedVector2Array:
	var sprout: float = params.get("sprout", 24.0)
	var bend: float = params.get("bend", 0.5)
	var trunk_top := from + Vector2(0.0, -sprout)
	var diagonal_point := trunk_top.lerp(to, 0.5)
	var squared_point := Vector2(to.x, trunk_top.y)
	var route_point := diagonal_point.lerp(squared_point, bend)
	return PackedVector2Array([from, trunk_top, route_point, to])


## True PCB / 45°-only route: a cardinal trunk out of `from`, then an exact 45°
## diagonal, then a cardinal run into `to` — every turn is 0°/45°/90°.
##
## `params.trunk_dir` (default up, `(0,-1)`) is the cardinal direction the trunk
## leaves along; `params.trunk` (default 0.382 ≈ φ) is the fraction of the trunk
## axis' span covered before the 45° break. That single fraction spans the whole
## family:
##   trunk == 0   → a pure 45° diagonal straight from `from`, then a cardinal leg
##   trunk ≈ φ    → trunk, 45° diagonal, cardinal leg (the classic sprout)
##   trunk == 1   → full cardinal leg then a squared 90° corner (no diagonal)
##
## `params.trunk_px` (default 0 = off) overrides `trunk` with a FIXED trunk
## length in pixels, clamped to the trunk axis' span. A fraction gives near
## panels short trunks and far panels long ones; a fixed length makes every
## trace in a fan leave its origin in a uniform bundle before diverging.
##
## The diagonal consumes `min(|rem.x|, |rem.y|)` on both axes, which snaps one
## axis onto `to`, so the closing leg is exactly cardinal. Consecutive duplicate
## points (produced at the 0 and 1 extremes) are removed so the polyline carries
## no zero-length segment.
##
## Two families share this entry, chosen by where `to` sits relative to the
## trunk top: AHEAD of it (a positive component along `trunk_dir`) takes the
## trunk → diagonal → cardinal route above; anywhere else takes the GABLE —
## trunk, 45° shoulder out, a run perpendicular to the trunk, the mirror 45°
## shoulder back, then a cardinal closing leg back along `-trunk_dir` into `to`.
## The gable's trunk is `trunk_px` if set, else `trunk` × the PERPENDICULAR span
## (the along-trunk span is meaningless behind the trunk top); its shoulder is
## `min(|perp| / 2, params.shoulder)` with `shoulder` defaulting to the trunk
## length, so a narrow perpendicular offset collapses the run to a 5-point arch.
##
## The invariant both families keep, for every target: every segment heading is
## on the 45° grid, no bend exceeds 90° (never a 135° double-back), and the
## closing leg is cardinal. Degenerate: a target behind the trunk top with
## `|perp| < 2 px` is outside the family (it is the trunk's own column, which
## the fan layout keeps panels out of) — the route still returns `first == from`
## and `last == to`, but with no shoulder room it is a straight cardinal line
## through the origin, tolerated rather than special-cased.
static func _pcb(from: Vector2, to: Vector2, params: Dictionary) -> PackedVector2Array:
	var trunk_frac: float = params.get("trunk", 0.382)
	var trunk_dir: Vector2 = params.get("trunk_dir", Vector2(0.0, -1.0))
	if trunk_dir == Vector2.ZERO:
		trunk_dir = Vector2(0.0, -1.0)
	trunk_dir = trunk_dir.normalized()
	var trunk_px: float = params.get("trunk_px", 0.0)
	var d := to - from
	var along := d.dot(trunk_dir)
	var span := absf(along)
	if along > 0.0 and (trunk_px <= 0.0 or trunk_px < along):
		# Ahead of the trunk top: the classic trunk → 45° diagonal → cardinal.
		# `trunk_px` (when > 0) overrides the fraction with a fixed length, clamped
		# so it can't overshoot the trunk axis and force the diagonal to double back.
		var trunk_len := minf(trunk_px, span) if trunk_px > 0.0 else trunk_frac * span
		var trunk_top := from + trunk_dir * trunk_len
		var rem := to - trunk_top
		var diag := minf(absf(rem.x), absf(rem.y))
		var diag_end := trunk_top + Vector2(signf(rem.x), signf(rem.y)) * diag
		return _dedup(PackedVector2Array([from, trunk_top, diag_end, to]))
	return _gable(from, to, trunk_dir, trunk_frac, trunk_px, params)


## The below-trunk-top family of [method _pcb]: U → (R|L)U → (R|L) → (R|L)D → D
## in the trunk's frame, symmetric shoulders. Written for a general cardinal
## `trunk_dir` (Roots' trunk points down).
static func _gable(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float, trunk_px: float, params: Dictionary) -> PackedVector2Array:
	var perp_dir := Vector2(-trunk_dir.y, trunk_dir.x)
	var d := to - from
	var perp := d.dot(perp_dir)
	var perp_abs := absf(perp)
	var side := signf(perp) if perp_abs > 0.0 else 1.0
	var trunk_len := trunk_px if trunk_px > 0.0 else trunk_frac * perp_abs
	var shoulder: float = params.get("shoulder", trunk_len)
	var a := minf(perp_abs / 2.0, shoulder)
	var b := perp_abs - 2.0 * a
	var trunk_top := from + trunk_dir * trunk_len
	var shoulder_out := trunk_top + (trunk_dir + perp_dir * side) * a
	var run_end := shoulder_out + perp_dir * side * b
	var shoulder_back := run_end + (-trunk_dir + perp_dir * side) * a
	return _dedup(PackedVector2Array([from, trunk_top, shoulder_out, run_end, shoulder_back, to]))


## Drops consecutive points that are equal (approx), preserving order and always
## keeping the first and last. Guards the reveal's arc-length walk against
## zero-length segments.
static func _dedup(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var out := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		if not points[i].is_equal_approx(out[out.size() - 1]):
			out.append(points[i])
	if out.size() < 2:
		out.append(points[points.size() - 1])
	return out
