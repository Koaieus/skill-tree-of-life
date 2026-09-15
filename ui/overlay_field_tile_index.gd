class_name OverlayFieldTileIndex
extends RefCounted

## World-space uniform-grid tile index over a circle-field overlay's circles,
## shared by [FogOverlay] and [AuraOverlay]. Packs the circle set and a
## tile → (offset, count) lookup into data textures so the fragment shader can
## read only its own 3×3 tile neighbourhood instead of looping every circle in
## the scene. See #177 and docs/domain/overlay-field-rendering.md.
##
## [b]Cell size = reach, same proof as [code]VisionSourceIndex[/code].[/b]
## `field_smin(a, b, k)` erases any contribution at least `k` past the running
## minimum (see that class's docstring for the full argument): a circle only
## matters at a query point while its normalized distance is `< 1 + k`, i.e.
## its centre is within `(1 + k) * its own radius`. `max_radius` bounds that
## over the whole set, so a grid whose cell size equals that reach answers any
## query from its 3×3 neighbourhood — no candidate is ever missed.
##
## [b]Circles are bucketed into exactly one cell each[/b] (the cell containing
## their centre); the 3×3 gather happens at QUERY time (GPU: per pixel, CPU:
## per [method gather_tile_order] call), not at build time. So the flat index
## buffer this produces has exactly `circle_count` entries — no duplication.
##
## [b]Cones (#897) are bucketed into every cell their segment's AABB touches[/b]
## — a long edge genuinely reaches into many cells, and the alternative
## (inflating `cell_size` to half the longest segment) makes every cell on the
## board hostage to one long Delaunay bridge. Multi-cell bucketing means a
## gather's 3×3 can meet the same primitive several times, and `field_smin` is
## NOT idempotent (`smin(d, d, k) == d - k/4`), so a double-fold would deepen
## the field in a grid-correlated pattern. The fix is the [b]projection-dedupe
## invariant[/b]: a primitive contributes only from the tile whose cell
## contains `q`, the clamped orthogonal projection of the query point onto the
## segment ([method OverlayFieldCone.project]).
##
## That is exact, not just duplicate-free. If the cone contributes at `p` at
## all then `|p - c(t)| < (1 + k) * max_radius == cell_size` for some `t` on
## the segment, and `q` is the segment's closest point, so `|p - q| <=
## cell_size` — `q`'s cell is inside `p`'s 3×3 and the primitive is seen.
## Dropping it when `q`'s cell is outside the 3×3 therefore drops nothing that
## could have contributed.
##
## [b]A circle is a degenerate cone[/b] (`a == b`, `ra == rb`), so both
## [method build] and [method build_cones] run the same bucketing and the same
## gather. For a circle `project` returns the stored `a` untouched, whose cell
## is by construction the one cell it was bucketed into — so the dedupe test
## always passes and [method gather_tile_order] is bit-identical to the
## pre-cone behaviour. The two paths differ only in how they SERIALIZE to the
## GPU: fog keeps its 1-texel `circles_texture`, cones use the 2-texel
## `primitives_texture`. `test_tile_gather_fold_order_drift.gd` and
## `test_vision_source_index.gd` guard that, unmodified.
##
## [b]Order is NOT global circle-index order.[/b] The shader visits tiles in
## (dx, dy) scan order and, within a tile, bucket-insertion order (which IS
## global order, since circles are inserted in the order passed to
## [method build]). `field_smin` is not associative, so this measurably
## differs from folding in pure global order — measured max drift 0.0026
## against a visible threshold of 1/255 = 0.0039 in
## test_tile_gather_fold_order_drift.gd. Any CPU consumer needing lockstep
## with the shader (FogOverlay's per-element dimming) MUST walk
## [method gather_tile_order], never re-sort it back to ascending index.

var circle_count: int = 0
var grid_cols: int = 0
var grid_rows: int = 0
var cell_size: float = 0.0
var grid_origin: Vector2 = Vector2.ZERO

## Alias of `circle_count` for the cone path, where "circle" is the wrong word.
var primitive_count: int = 0

var circles_texture: ImageTexture
## The cone path's serialization: two RGBAF texels per primitive,
## `(ax, ay, ra, tag)` then `(bx, by, rb, 0)`. Null after [method build].
var primitives_texture: ImageTexture
var tile_index_texture: ImageTexture
var tile_circle_indices_texture: ImageTexture

# Cell (Vector2i) → Array[int] of primitive indices, in build (= global) order.
# Kept for gather_tile_order; the textures are the GPU-facing serialization
# of the same data.
var _cells: Dictionary = {}
var _circles: Array = []
var _cones: Array = []
var _degenerate: bool = true

# Unpacked primitive endpoints, shared by both build paths — a circle is stored
# as a == b. gather_tile_order's dedupe reads these and nothing else.
var _ends_a: Array[Vector2] = []
var _ends_b: Array[Vector2] = []


## `circles` is `Array[Vector4]`: `(world_x, world_y, radius, tag)`. `tag` is
## opaque to this class — FogOverlay uses it for `motion`, AuraOverlay for
## `entity_index`.
func build(circles: Array, union_smoothness: float) -> void:
	_reset()
	_circles = circles
	circle_count = circles.size()
	primitive_count = circle_count
	for c in circles:
		var centre := Vector2(c.x, c.y)
		_ends_a.append(centre)
		_ends_b.append(centre)
	if _bin(union_smoothness):
		_build_circle_texture()
		_build_tile_textures()


## Cone build path (#897). `cones` is `Array[Vector4]` of length `2 * n`, laid
## out exactly as the GPU reads it: `(ax, ay, ra, tag)` then `(bx, by, rb, 0)`
## per primitive, so the upload is a straight copy. An odd trailing element is
## ignored. `tag` is opaque here — AuraOverlay uses it for `entity_index`.
##
## Every owned node ships as a degenerate cone (`a == b`, `ra == rb`)
## regardless of degree, so an isolated node still draws; see #140 decision 6.
func build_cones(cones: Array, union_smoothness: float) -> void:
	_reset()
	_cones = cones
	primitive_count = cones.size() / 2
	circle_count = primitive_count
	for i in primitive_count:
		_ends_a.append(Vector2(cones[i * 2].x, cones[i * 2].y))
		_ends_b.append(Vector2(cones[i * 2 + 1].x, cones[i * 2 + 1].y))
	if _bin(union_smoothness):
		_build_primitives_texture()
		_build_tile_textures()


func _reset() -> void:
	_cells.clear()
	_circles = []
	_cones = []
	_ends_a.clear()
	_ends_b.clear()
	circle_count = 0
	primitive_count = 0
	_degenerate = true
	grid_cols = 0
	grid_rows = 0
	cell_size = 0.0
	grid_origin = Vector2.ZERO
	circles_texture = null
	primitives_texture = null
	tile_index_texture = null
	tile_circle_indices_texture = null


# Shared grid sizing + bucketing over `_ends_a` / `_ends_b`. Returns false when
# there is nothing to index (both build paths then leave every texture null).
func _bin(union_smoothness: float) -> bool:
	if primitive_count <= 0:
		return false

	var max_radius: float = 0.0
	var min_pos := _ends_a[0]
	var max_pos := min_pos
	for i in primitive_count:
		max_radius = maxf(max_radius, maxf(_radius_of(i, 0), _radius_of(i, 1)))
		for p in [_ends_a[i], _ends_b[i]]:
			min_pos.x = minf(min_pos.x, p.x)
			min_pos.y = minf(min_pos.y, p.y)
			max_pos.x = maxf(max_pos.x, p.x)
			max_pos.y = maxf(max_pos.y, p.y)

	cell_size = (1.0 + maxf(union_smoothness, 0.0)) * max_radius
	if cell_size <= 0.0:
		# Degenerate (every radius clamps to the same non-positive value —
		# unreachable in practice, since radius is floored to >= 1.0 before it
		# reaches this class; kept for defensiveness).
		return false
	_degenerate = false

	# Grid must cover every circle's OWN cell, expanded by one so a query just
	# outside the bounding box still finds its 3x3 neighbourhood on the grid.
	#
	# The extra 1e-4 * cell_size margin matters: without it, `min_pos - cell_size`
	# puts the bounding box's own extremal circle EXACTLY on a cell boundary
	# (its distance from origin is exactly one cell_size, i.e. floor() lands on
	# 1.0 precisely). Floating-point rounding at that knife-edge is order-of-
	# operations-dependent, so two algebraically-identical but differently-coded
	# computations of the same floor (e.g. this class vs. GLSL in the shader, or
	# vs. an independent test transcription) can round to DIFFERENT cells for
	# that one circle — moving it in or out of a query's 3x3 neighbourhood.
	# Measured empirically: a 0.0022 CPU/reference darkness mismatch, traced to
	# exactly this. The margin pushes every real circle's cell coordinate
	# strictly away from any boundary.
	grid_origin = min_pos - Vector2(cell_size, cell_size) - Vector2(cell_size, cell_size) * 1e-4
	grid_cols = maxi(1, floori((max_pos.x - grid_origin.x) / cell_size) + 2)
	grid_rows = maxi(1, floori((max_pos.y - grid_origin.y) / cell_size) + 2)

	# Bucket every cell the segment's AABB touches. For a circle (a == b) that
	# is the single cell containing the centre — the pre-cone behaviour, and
	# the reason the fog path's gather is unchanged.
	for i in primitive_count:
		var lo := _cell_of(_ends_a[i].min(_ends_b[i]))
		var hi := _cell_of(_ends_a[i].max(_ends_b[i]))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var cell := Vector2i(cx, cy)
				if not _cells.has(cell):
					_cells[cell] = []
				(_cells[cell] as Array).append(i)
	return true


func _radius_of(i: int, which: int) -> float:
	if _cones.is_empty():
		return maxf(_circles[i].z, 1.0)
	return maxf(_cones[i * 2 + which].z, 1.0)


## Indices of every circle that can contribute at `world_pos`, in the SAME
## order the shader visits them: tiles in (dx, dy) scan order, each tile's
## circles in build (global-insertion) order. See the class docstring — this
## is the order any CPU-side fold must use to stay in lockstep with the GPU.
func gather_tile_order(world_pos: Vector2) -> Array:
	if _degenerate:
		var all: Array = []
		for i in primitive_count:
			all.append(i)
		return all
	var out: Array = []
	var centre := _cell_of(world_pos)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var cell := centre + Vector2i(dx, dy)
			var bucket: Array = _cells.get(cell, [])
			for i in bucket:
				# Projection dedupe — see the class docstring. A primitive is
				# taken only from the tile owning its projection, so a segment
				# spanning several of the 3×3 cells is folded exactly once.
				# This FILTERS, never reorders: circles always pass (their
				# projection is their own centre, hence their own cell), so the
				# fog path's traversal order is untouched.
				if _cell_of(OverlayFieldCone.project(world_pos, _ends_a[i], _ends_b[i])) == cell:
					out.append(i)
	return out


func get_circle(i: int) -> Vector4:
	return _circles[i]


## The two raw texels of cone `i`, `(ax, ay, ra, tag)` and `(bx, by, rb, 0)`.
func get_cone(i: int) -> Array:
	return [_cones[i * 2], _cones[i * 2 + 1]]


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - grid_origin.x) / cell_size), floori((p.y - grid_origin.y) / cell_size))


func _build_circle_texture() -> void:
	var circles_img := Image.create(maxi(circle_count, 1), 1, false, Image.FORMAT_RGBAF)
	for i in circle_count:
		var c: Vector4 = _circles[i]
		circles_img.set_pixel(i, 0, Color(c.x, c.y, c.z, c.w))
	circles_texture = ImageTexture.create_from_image(circles_img)


# Two RGBAF texels per cone, in the order the caller packed them.
func _build_primitives_texture() -> void:
	var img := Image.create(maxi(primitive_count * 2, 1), 1, false, Image.FORMAT_RGBAF)
	for i in primitive_count * 2:
		var v: Vector4 = _cones[i]
		img.set_pixel(i, 0, Color(v.x, v.y, v.z, v.w))
	primitives_texture = ImageTexture.create_from_image(img)


func _build_tile_textures() -> void:
	# NOT primitive_count: a cone lives in every cell its AABB touches, so the
	# flat buffer is as long as the total bucket population.
	var entries := 0
	for bucket in _cells.values():
		entries += (bucket as Array).size()

	var tile_index_img := Image.create(grid_cols, grid_rows, false, Image.FORMAT_RGF)
	var tile_indices_img := Image.create(maxi(entries, 1), 1, false, Image.FORMAT_RF)

	var offset := 0
	# Iterate tiles in row-major order so the flat index buffer's layout is
	# deterministic and independent of Dictionary iteration order.
	for row in grid_rows:
		for col in grid_cols:
			var cell := Vector2i(col, row)
			var bucket: Array = _cells.get(cell, [])
			tile_index_img.set_pixel(col, row, Color(float(offset), float(bucket.size()), 0.0, 0.0))
			for idx in bucket:
				tile_indices_img.set_pixel(offset, 0, Color(float(idx), 0.0, 0.0, 0.0))
				offset += 1
	tile_index_texture = ImageTexture.create_from_image(tile_index_img)
	tile_circle_indices_texture = ImageTexture.create_from_image(tile_indices_img)
