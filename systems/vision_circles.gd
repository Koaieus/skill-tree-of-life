class_name VisionCircles
extends RefCounted

## A set of vision circles plus the one rule that reads them: "is this point
## inside the union?". [VisionSystem] and [AiRecon] both build one, so the rule
## never forks. Carries a lazily built uniform grid (cell = largest radius, 3x3
## scan is exact). Do not merge it with [OverlayFieldTileIndex]: they differ in
## cell size, margins, storage and semantics (rejected 2026-08-17).
## See docs/domain/vision-system.md "VisionCircles".

## Grid resolution ceiling per axis. A pathological set (one huge circle and one
## pinprick, spread across the map) would otherwise ask for a cell count
## quadratic in the map size; past this the cells simply get coarser, which
## costs query time but never correctness.
const _MAX_CELLS_PER_AXIS := 128

var _positions := PackedVector2Array()
var _radii := PackedFloat32Array()
var _max_radius: float = 0.0

# Lazily built index. `_cells[row * _cols + col]` is a PackedInt32Array of
# indices into `_positions`. Empty `_cells` means "not built yet".
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
	for dr in range(maxi(row - 1, 0), mini(row + 1, _rows - 1) + 1):
		var base := dr * _cols
		for dc in range(maxi(col - 1, 0), mini(col + 1, _cols - 1) + 1):
			var bucket: PackedInt32Array = _cells[base + dc]
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

	# Cell size = max radius makes the 3x3 neighbourhood exact. Guard the
	# degenerate all-zero-radius set, and coarsen rather than explode when the
	# span/radius ratio is extreme.
	_cell_size = maxf(_max_radius, 1.0)
	var span := _hi - _lo
	_cell_size = maxf(_cell_size, maxf(span.x, span.y) / float(_MAX_CELLS_PER_AXIS))
	_cols = maxi(int(span.x / _cell_size) + 1, 1)
	_rows = maxi(int(span.y / _cell_size) + 1, 1)

	_cells.resize(_cols * _rows)
	for i in _cells.size():
		_cells[i] = PackedInt32Array()
	for i in _positions.size():
		var pos := _positions[i]
		var col := clampi(int((pos.x - _lo.x) / _cell_size), 0, _cols - 1)
		var row := clampi(int((pos.y - _lo.y) / _cell_size), 0, _rows - 1)
		_cells[row * _cols + col].append(i)
