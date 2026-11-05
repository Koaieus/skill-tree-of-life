class_name VisionCircles
extends RefCounted

## A set of vision circles plus the one rule that reads them: "is this point
## inside the union?". [VisionSystem] and [AiRecon] both build one, so the rule
## never forks. Carries a lazily built uniform grid whose cells (a fraction of the
## largest radius) are classified full/empty/partial at build, so a query is one
## cell lookup and stays exact. Do not merge it with [OverlayFieldTileIndex]: they differ in
## cell size, margins, storage and semantics (rejected 2026-08-17).
## See docs/domain/vision-system.md "VisionCircles".

## Grid resolution ceiling per axis. A pathological set (one huge circle and one
## pinprick, spread across the map) would otherwise ask for a cell count
## quadratic in the map size; past this the cells simply get coarser, which
## costs query time but never correctness.
const _MAX_CELLS_PER_AXIS := 128
## Cells per largest radius. Build visits ~(2 * divisor + 2)^2 cells per circle
## at most; partial-cell scans shrink as the divisor grows. Swept 2/3/4 on
## `bench_allocation_cost.gd` at 200 owned (build + query): 2 won, because the
## build is the larger term there and the query is dominated by its per-call
## floor, not by scanning. Tentative.
const _CELL_DIVISOR := 2
## Slack, as a fraction of a cell, on both classification tests (see the
## class comment): wide enough to swallow float32 rounding at any map size this
## project targets, narrow enough that it never promotes a full cell to partial
## in practice.
const _EPS_FRAC := 1e-3

var _positions := PackedVector2Array()
var _radii := PackedFloat32Array()
var _max_radius: float = 0.0

# Lazily built index, row-major `row * _cols + col`. `_full[i] == 1` means the
# cell is wholly inside the union; `_cells[i]` is null (no circle reaches the
# cell) or a PackedInt32Array of indices into `_positions` whose circles cross
# it. Empty `_cells` means "not built yet".
var _full := PackedByteArray()
var _cells: Array = []
var _cols: int = 0
var _rows: int = 0
var _cell_size: float = 0.0
# Inclusive bounds of the reachable region: the centres' box grown by the
# largest radius. Anything outside is rejected without touching a cell.
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO


## Adds one source circle. Radii of 0 are kept, not dropped: the union rule is
## `distance <= radius`, so a zero-radius circle still contains its own centre,
## and an owned node with no vision must still see itself.
func add(pos: Vector2, radius: float) -> void:
	_positions.append(pos)
	_radii.append(radius)
	_max_radius = maxf(_max_radius, radius)
	_cells.clear()


func size() -> int:
	return _positions.size()


func is_empty() -> bool:
	return _positions.is_empty()


## The vision rule. True iff [param p] lies inside at least one circle.
func has_point(p: Vector2) -> bool:
	if _positions.is_empty():
		return false
	if _cells.is_empty():
		_build_index()
	# Inclusive on all four sides. `Rect2.has_point` is not (it excludes the
	# far edge, and a zero-size rect contains nothing), and the union rule is
	# `distance <= radius` — a point exactly on the rim IS visible.
	if p.x < _lo.x or p.y < _lo.y or p.x > _hi.x or p.y > _hi.y:
		return false
	var col := clampi(int((p.x - _lo.x) / _cell_size), 0, _cols - 1)
	var row := clampi(int((p.y - _lo.y) / _cell_size), 0, _rows - 1)
	var idx := row * _cols + col
	if _full[idx] != 0:
		return true
	var bucket = _cells[idx]
	if bucket == null:
		return false
	for i in bucket:
		var r := _radii[i]
		if p.distance_squared_to(_positions[i]) <= r * r:
			return true
	return false


func _build_index() -> void:
	var lo := _positions[0]
	var hi := _positions[0]
	for i in range(1, _positions.size()):
		lo = lo.min(_positions[i])
		hi = hi.max(_positions[i])
	# The reachable region is the centres' box grown by the largest radius;
	# anything outside it is rejected by the bounds test alone.
	var margin := Vector2(_max_radius, _max_radius)
	_lo = lo - margin
	_hi = hi + margin

	# Guard the degenerate all-zero-radius set, and coarsen rather than
	# explode when the span/radius ratio is extreme.
	_cell_size = maxf(_max_radius / float(_CELL_DIVISOR), 1.0)
	var span := _hi - _lo
	_cell_size = maxf(_cell_size, maxf(span.x, span.y) / float(_MAX_CELLS_PER_AXIS))
	_cols = maxi(int(span.x / _cell_size) + 1, 1)
	_rows = maxi(int(span.y / _cell_size) + 1, 1)

	var cs := _cell_size
	var eps := cs * _EPS_FRAC
	var lox := float(_lo.x)
	var loy := float(_lo.y)
	# resize() only — the cells are nulls until a circle crosses them, so a
	# 128x128 grid never allocates 16k empty buckets up front.
	_full.resize(_cols * _rows)
	_full.fill(0)
	_cells.resize(_cols * _rows)
	_cells.fill(null)

	for i in _positions.size():
		var cx := float(_positions[i].x)
		var cy := float(_positions[i].y)
		var r_out := float(_radii[i]) + eps  # a circle this big TOUCHES a cell
		var r_in := float(_radii[i]) - eps  # a cell inside THIS is full
		var r_out2 := r_out * r_out
		var r_in2 := r_in * r_in
		var row0 := maxi(floori((cy - r_out - loy) / cs), 0)
		var row1 := mini(floori((cy + r_out - loy) / cs), _rows - 1)
		for row in range(row0, row1 + 1):
			var y0 := loy + row * cs
			var y1 := y0 + cs
			# Nearest and farthest the row's band gets to the centre, in y.
			var dy_near := 0.0 if (y0 <= cy and cy <= y1) else minf(absf(cy - y0), absf(cy - y1))
			if dy_near > r_out:
				continue
			var half_out := sqrt(r_out2 - dy_near * dy_near)
			var c0 := maxi(floori((cx - half_out - lox) / cs), 0)
			var c1 := mini(floori((cx + half_out - lox) / cs), _cols - 1)
			if c0 > c1:
				continue
			# Columns whose whole square sits inside the shrunk circle: both
			# x-edges within the chord at the row's FARTHEST y. Empty range
			# (f1 < f0) when the row has none.
			var f0 := c1 + 1
			var f1 := c0 - 1
			var dy_far := maxf(absf(cy - y0), absf(cy - y1))
			if r_in > 0.0 and dy_far < r_in:
				var half_in := sqrt(r_in2 - dy_far * dy_far)
				f0 = maxi(ceili((cx - half_in - lox) / cs), c0)
				f1 = mini(floori((cx + half_in - lox) / cs) - 1, c1)
			var base := row * _cols
			for c in range(f0, f1 + 1):
				_full[base + c] = 1
			# The rim columns either side of the full run. A cell some other
			# circle already covers whole needs no entry: the query never
			# reaches its list.
			for c in range(c0, mini(f0, c1 + 1)):
				var idx := base + c
				if _full[idx] == 0:
					var bucket = _cells[idx]
					if bucket == null:
						_cells[idx] = PackedInt32Array([i])
					else:
						bucket.append(i)
			for c in range(maxi(f1 + 1, f0), c1 + 1):
				var idx := base + c
				if _full[idx] == 0:
					var bucket = _cells[idx]
					if bucket == null:
						_cells[idx] = PackedInt32Array([i])
					else:
						bucket.append(i)
