@tool
class_name SkillNodeGrid
extends RefCounted

## A uniform grid over SkillNode CENTRES plus one running [member max_radius]:
## the board's candidate source for straight-line reach gathers
## ([method Graph.spatial_candidates] owns one, [EuclideanRangeFinder] reads it).
##
## It only narrows. [method candidates_within] returns every node whose centre
## lies in a cell touching the circle `(centre, reach + max_radius)` — a
## superset of the exact hitbox-touching set, since a disc of radius
## `r <= max_radius` can touch the reach circle only if its centre is within
## `reach + max_radius`. [method EuclideanRangeFinder._reaches] still decides,
## so a stale grid can only over-include (a radius that shrank) or miss (a
## position written after the build) — never admit a node the predicate
## rejects.
##
## Each bucket keeps the order [method rebuild] was handed (Graph hands
## `stable_id` order), so a host and a peer walk identical candidates whatever
## their container child order. Plain arrays, no signals: readable from any
## thread while nothing rebuilds it.

## Guard against a pathological span/cell ratio, not a feel knob: past it the
## cell coarsens, the allocation never grows.
const MAX_CELLS_PER_AXIS := 128

## Largest node radius seen — exact at [method rebuild], only raised after.
var max_radius: float = 0.0
var cols: int = 0
var rows: int = 0
## Effective cell edge in px (the requested one, coarsened by the axis cap).
var cell: float = 128.0

var _origin := Vector2.ZERO
## Flat `cols * rows` buckets, each an Array[SkillNode].
var _cells: Array[Array] = []
var _count: int = 0


## Bin [param nodes] by centre, reading each node's `global_position` and
## `radius` once. [param cell_px] is the requested cell edge.
func rebuild(nodes: Array[SkillNode], cell_px: float) -> void:
	_cells = []
	_count = nodes.size()
	max_radius = 0.0
	cols = 0
	rows = 0
	if nodes.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in nodes:
		var p := n.global_position
		lo = lo.min(p)
		hi = hi.max(p)
		max_radius = maxf(max_radius, n.radius)
	_origin = lo
	var span := hi - lo
	cell = maxf(maxf(cell_px, 1.0), maxf(span.x, span.y) / float(MAX_CELLS_PER_AXIS))
	cols = mini(int(span.x / cell) + 1, MAX_CELLS_PER_AXIS)
	rows = mini(int(span.y / cell) + 1, MAX_CELLS_PER_AXIS)
	_cells.resize(cols * rows)
	for i in _cells.size():
		_cells[i] = [] as Array[SkillNode]
	for n in nodes:
		var p := n.global_position - _origin
		var cx := clampi(int(p.x / cell), 0, cols - 1)
		var cy := clampi(int(p.y / cell), 0, rows - 1)
		_cells[cy * cols + cx].append(n)


## A node's radius grew after the build: widen the margin. Never lowers it —
## over-inclusive is safe, stale-low would miss.
func note_radius(r: float) -> void:
	max_radius = maxf(max_radius, r)


## Every node whose centre lies in a cell touching the circle
## `(centre, reach + max_radius)`, bucket by bucket (row-major), each bucket in
## build order. A fresh array per call.
func candidates_within(centre: Vector2, reach: float) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if _count == 0:
		return out
	var expand := maxf(reach, 0.0) + max_radius
	var e2 := expand * expand
	var x0 := clampi(int(floorf((centre.x - expand - _origin.x) / cell)), 0, cols - 1)
	var x1 := clampi(int(floorf((centre.x + expand - _origin.x) / cell)), 0, cols - 1)
	var y0 := clampi(int(floorf((centre.y - expand - _origin.y) / cell)), 0, rows - 1)
	var y1 := clampi(int(floorf((centre.y + expand - _origin.y) / cell)), 0, rows - 1)
	for cy in range(y0, y1 + 1):
		var ry0 := _origin.y + cy * cell
		# The last row/column also holds whatever the clamp folded into it, so
		# its far edge is open for the nearest-point reject.
		var ry1 := INF if cy == rows - 1 else ry0 + cell
		var ny := clampf(centre.y, ry0 if cy > 0 else -INF, ry1) - centre.y
		for cx in range(x0, x1 + 1):
			var rx0 := _origin.x + cx * cell
			var rx1 := INF if cx == cols - 1 else rx0 + cell
			var nx := clampf(centre.x, rx0 if cx > 0 else -INF, rx1) - centre.x
			if nx * nx + ny * ny > e2:
				continue
			out.append_array(_cells[cy * cols + cx])
	return out


func is_empty() -> bool:
	return _count == 0
