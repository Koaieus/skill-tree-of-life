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
## The diagonal consumes `min(|rem.x|, |rem.y|)` on both axes, which snaps one
## axis onto `to`, so the closing leg is exactly cardinal. Consecutive duplicate
## points (produced at the 0 and 1 extremes) are removed so the polyline carries
## no zero-length segment.
static func _pcb(from: Vector2, to: Vector2, params: Dictionary) -> PackedVector2Array:
	var trunk_frac: float = params.get("trunk", 0.382)
	var trunk_dir: Vector2 = params.get("trunk_dir", Vector2(0.0, -1.0))
	if trunk_dir == Vector2.ZERO:
		trunk_dir = Vector2(0.0, -1.0)
	trunk_dir = trunk_dir.normalized()
	var d := to - from
	var trunk_len := trunk_frac * absf(d.dot(trunk_dir))
	var trunk_top := from + trunk_dir * trunk_len
	var rem := to - trunk_top
	var diag := minf(absf(rem.x), absf(rem.y))
	var diag_end := trunk_top + Vector2(signf(rem.x), signf(rem.y)) * diag
	return _dedup(PackedVector2Array([from, trunk_top, diag_end, to]))


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
