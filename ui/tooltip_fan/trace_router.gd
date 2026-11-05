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


## True PCB / 45-degree-only route: a cardinal trunk out of `from`, an exact 45
## diagonal, then a cardinal run into `to`. `params.trunk_dir` (default up),
## `params.trunk` (fraction, default 0.382) or `params.trunk_px` (fixed length)
## shape the trunk. A target level with or behind the trunk top takes the GABLE
## instead. Every heading is on the 45 grid and the closing leg is cardinal.
## See docs/domain/tooltip-fan-units.md
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
