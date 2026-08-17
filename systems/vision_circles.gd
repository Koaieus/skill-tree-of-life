class_name VisionCircles
extends RefCounted

## A set of vision circles plus the one geometric rule that reads them:
## "is this point inside the union?". Both fog consumers build one of these —
## [VisionSystem] (the scene's shared, player-scoped instance) and [AiRecon]
## (a fresh per-entity set each AI turn) — so the vision rule never forks into
## two implementations.
##
## [b]Why this is a class and not a static predicate over two packed arrays[/b]
## (which is what it replaced): every caller asks the same question about
## [i]many[/i] points against the [i]same[/i] circles. A per-point linear scan is
## O(points x circles), and at the scale this project targets
## (see [code].claude/rules/skill-node-scale.md[/code] — ~2000 nodes, ~200 owned)
## that is 400k GDScript iterations per recompute, measured at 13.3ms of a
## 19.4ms [code]VisionSystem._recompute()[/code]. Owning the circle set lets it
## carry a spatial index that the scan could not.
##
## [b]The index[/b] is a uniform grid over the union's bounding box, with cell
## size = the largest radius. A circle centred at [code]c[/code] with radius
## [code]r <= max_radius[/code] can only contain [code]p[/code] when
## [code]|p - c| <= max_radius[/code], so [code]c[/code] must sit in
## [code]p[/code]'s cell or one of its 8 neighbours — a 3x3 scan is exact, not
## an approximation. Points outside the bounding box are rejected by four float
## comparisons, which is the common case (most of a level is fogged) and is
## where the win comes from.
##
## [b]Do not merge this grid with [OverlayFieldTileIndex][/b] (the fog overlay's
## tile index, via [VisionSourceIndex]). They look like the same uniform grid
## over the same circles, and they are not — investigated and rejected
## 2026-08-17:
##   - Cell size differs semantically: `max_radius` here vs
##     `(1 + union_smoothness) * max_radius` there, deliberately widened for the
##     smin fold's reach.
##   - Margins differ: 1x max_radius here; 2x cell_size plus a hand-tuned
##     `1e-4 * cell_size` epsilon there, which exists to fix a MEASURED
##     CPU/shader darkness mismatch from floor() boundary ties, with only 0.0013
##     of headroom under the visible threshold.
##   - Storage differs: a dense flat Array here; a sparse Dictionary there,
##     because it must also serialize into GPU data textures in deterministic
##     row-major order.
##   - This answers a hard boolean union; that answers a soft field fold whose
##     CPU walk must match the fragment shader's tile-gather order exactly.
## A shared substrate would need parameters for every one of those and would
## risk that epsilon. ~15-20 lines of superficial shape is not worth it.
##
## Build cost is O(circles) and lazy: adding a circle only invalidates the
## index, so a caller may [method add] freely and pay for the grid on its first
## query. A set queried once still beats the linear scan for any realistic node
## count.

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
