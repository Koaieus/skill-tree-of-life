## Tooltip V2 (#159 Phase 0) — pure geometry helper for fan-trace connectors.
##
## Decoupled from any fan orientation, layout, or node: given two points and a
## style, returns the polyline a trace line should follow. No randomness, no
## node dependencies — callers own how the points get drawn (Line2D, etc.).
class_name TraceRouter
extends RefCounted

enum Style { STRAIGHT, ELBOW, TREE, PCB }

## The shortest segment a PCB route may draw (the closing leg excepted, see
## [method _pcb]): a shorter one reads as a kink standing in for a 90° corner.
const MIN_SEGMENT_PX := 12.0
## The share of the sideways distance from the trunk top to a side panel's edge
## the 45° diagonal takes; the cardinal closing leg takes the rest. Read by
## [FanAnchor] to place the slide target, never passed as a route param.
const DIAGONAL_SHARE := 0.5


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
## diagonal, then a cardinal run into `to` — every turn is 0°/45°/90°, and no
## trunk ever cuts straight into a 90° corner.
##
## `params.trunk_dir` (default up, `(0,-1)`) is the cardinal direction the trunk
## leaves along; `params.trunk` (default 0.382 ≈ φ) is the fraction of the trunk
## axis' span covered before the 45° break:
##   trunk == 0   → a pure 45° diagonal straight from `from`, then a cardinal leg
##   trunk ≈ φ    → trunk, 45° diagonal, cardinal leg (the classic sprout)
##   trunk == 1   → the longest trunk that still leaves a [constant MIN_SEGMENT_PX]
##                  diagonal — the fraction is capped at `span − MIN_SEGMENT_PX`
##
## `params.trunk_px` (default 0 = off) overrides `trunk` with a FIXED trunk
## length in pixels, never shortened: a fraction gives near panels short trunks
## and far panels long ones; a fixed length makes every trace in a fan leave its
## origin in a uniform bundle before diverging (and lets
## `FanAnchorDriver.trunk_top_of` compute the trunk top by formula).
##
## The diagonal consumes `min(|rem.x|, |rem.y|)` on both axes, which snaps one
## axis onto `to`, so the closing leg is exactly cardinal. Consecutive duplicate
## points are removed so the polyline carries no zero-length segment.
##
## Two families share this entry, chosen by the target's along-trunk remainder
## past the trunk top: at least [constant MIN_SEGMENT_PX] AHEAD takes the
## trunk → diagonal → cardinal route above, so the diagonal is never
## `0 < diag < MIN_SEGMENT_PX`; anything nearer (level with the trunk top, or
## behind it) takes the GABLE — trunk, 45° shoulder out, a run perpendicular
## to the trunk, the 45° shoulder back, then a cardinal closing leg back along
## `-trunk_dir` into `to`. The gable's trunk is `trunk_px` if set, else `trunk`
## × the PERPENDICULAR span. Its shoulder `a` is `min(params.shoulder,
## avail / 3)` (`shoulder` defaulting to the trunk length) floored at
## [constant MIN_SEGMENT_PX] — a third each for two shoulders and the run; an
## `avail` under `3 × MIN_SEGMENT_PX` drops the run and splits it between the
## shoulders. A target level with or just past the trunk top LIFTS the gable:
## the outward shoulder runs longer than the return so the return lands
## [constant MIN_SEGMENT_PX] past `to` and the closing leg comes back down onto
## it; `avail` is the perpendicular span minus that lift.
##
## The invariant both families keep, for every target outside the degenerate
## zone: every segment heading is on the 45° grid, no bend exceeds 90° (never a
## 135° double-back), no two consecutive segments are both cardinal, every
## segment but the closing leg is at least [constant MIN_SEGMENT_PX], and the
## closing leg is cardinal — a gable's at least [constant MIN_SEGMENT_PX], an
## ahead route's the leftover `||rem.x| − |rem.y||` (zero on an exact 45°
## target, where the route ends on its diagonal). A fraction-mode trunk floors
## at [constant MIN_SEGMENT_PX] too, save `trunk == 0`, which draws none; a
## `trunk_px` under the minimum is the caller's call. Degenerate: `|perp|` under
## `2 × MIN_SEGMENT_PX` (the trunk's own column, which the fan layout keeps
## panels out of), or a lifted gable whose `avail` is under that — the route
## still returns `first == from` and `last == to`, with shoulders or a
## diagonal under the minimum, tolerated rather than special-cased.
static func _pcb(from: Vector2, to: Vector2, params: Dictionary) -> PackedVector2Array:
	var trunk_frac: float = params.get("trunk", 0.382)
	var trunk_dir: Vector2 = params.get("trunk_dir", Vector2(0.0, -1.0))
	if trunk_dir == Vector2.ZERO:
		trunk_dir = Vector2(0.0, -1.0)
	trunk_dir = trunk_dir.normalized()
	var trunk_px: float = params.get("trunk_px", 0.0)
	var d := to - from
	var along := d.dot(trunk_dir)
	var trunk_len := trunk_px
	var is_ahead := along - trunk_px >= MIN_SEGMENT_PX
	if trunk_px <= 0.0:
		var floor_px := _fraction_trunk_floor(trunk_frac)
		trunk_len = minf(maxf(trunk_frac * absf(along), floor_px), along - MIN_SEGMENT_PX)
		is_ahead = trunk_len >= floor_px
	if is_ahead:
		# Ahead of the trunk top by at least the minimum: the classic
		# trunk → 45° diagonal → cardinal, the diagonal never sub-minimum.
		var trunk_top := from + trunk_dir * trunk_len
		var rem := to - trunk_top
		var diag := minf(absf(rem.x), absf(rem.y))
		var diag_end := trunk_top + Vector2(signf(rem.x), signf(rem.y)) * diag
		return _dedup(PackedVector2Array([from, trunk_top, diag_end, to]))
	return _gable(from, to, trunk_dir, trunk_frac, trunk_px, params)


## The level-or-behind family of [method _pcb]: U → (R|L)U → (R|L) → (R|L)D → D
## in the trunk's frame. Written for a general cardinal `trunk_dir` (Roots'
## trunk points down).
static func _gable(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float, trunk_px: float, params: Dictionary) -> PackedVector2Array:
	var perp_dir := Vector2(-trunk_dir.y, trunk_dir.x)
	var d := to - from
	var perp := d.dot(perp_dir)
	var perp_abs := absf(perp)
	var side := signf(perp) if perp_abs > 0.0 else 1.0
	var trunk_len := trunk_px
	if trunk_px <= 0.0:
		trunk_len = maxf(trunk_frac * perp_abs, _fraction_trunk_floor(trunk_frac))
	# `to`'s offset along the trunk past the trunk top; the return shoulder lands
	# `lift` past it so the closing leg (along -trunk_dir) is at least the minimum.
	var ahead := d.dot(trunk_dir) - trunk_len
	var lift := minf(maxf(0.0, ahead + MIN_SEGMENT_PX), perp_abs)
	var avail := perp_abs - lift
	var shoulder: float = params.get("shoulder", trunk_len)
	var a := avail / 3.0
	if avail >= 3.0 * MIN_SEGMENT_PX:
		a = clampf(shoulder, MIN_SEGMENT_PX, avail / 3.0)
	elif avail >= 2.0 * MIN_SEGMENT_PX:
		a = avail / 2.0
	var b := avail - 2.0 * a
	var trunk_top := from + trunk_dir * trunk_len
	var shoulder_out := trunk_top + (trunk_dir + perp_dir * side) * (a + lift)
	var run_end := shoulder_out + perp_dir * side * b
	var shoulder_back := run_end + (-trunk_dir + perp_dir * side) * a
	return _dedup(PackedVector2Array([from, trunk_top, shoulder_out, run_end, shoulder_back, to]))


## The shortest trunk a fraction-mode route draws: none for `trunk == 0` (the
## route starts on its diagonal), else [constant MIN_SEGMENT_PX].
static func _fraction_trunk_floor(trunk_frac: float) -> float:
	return MIN_SEGMENT_PX if trunk_frac > 0.0 else 0.0


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
