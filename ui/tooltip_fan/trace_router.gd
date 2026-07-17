## Tooltip V2 (#159 Phase 0) — pure geometry helper for fan-trace connectors.
##
## Decoupled from any fan orientation, layout, or node: given two points and a
## style, returns the polyline a trace line should follow. No randomness, no
## node dependencies — callers own how the points get drawn (Line2D, etc.).
class_name TraceRouter
extends RefCounted

enum Style { STRAIGHT, ELBOW, TREE }


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
