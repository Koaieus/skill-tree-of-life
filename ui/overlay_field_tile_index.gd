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

var circles_texture: ImageTexture
var tile_index_texture: ImageTexture
var tile_circle_indices_texture: ImageTexture

# Cell (Vector2i) → Array[int] of circle indices, in build (= global) order.
# Kept for gather_tile_order; the textures are the GPU-facing serialization
# of the same data.
var _cells: Dictionary = {}
var _circles: Array = []
var _degenerate: bool = true


## `circles` is `Array[Vector4]`: `(world_x, world_y, radius, tag)`. `tag` is
## opaque to this class — FogOverlay uses it for `motion`, AuraOverlay for
## `entity_index`.
func build(circles: Array, union_smoothness: float) -> void:
	_cells.clear()
	_circles = circles
	circle_count = circles.size()
	_degenerate = true
	grid_cols = 0
	grid_rows = 0
	cell_size = 0.0
	grid_origin = Vector2.ZERO
	if circles.is_empty():
		circles_texture = null
		tile_index_texture = null
		tile_circle_indices_texture = null
		return

	var max_radius: float = 0.0
	var min_pos := Vector2(circles[0].x, circles[0].y)
	var max_pos := min_pos
	for c in circles:
		var r: float = maxf(c.z, 1.0)
		max_radius = maxf(max_radius, r)
		min_pos.x = minf(min_pos.x, c.x)
		min_pos.y = minf(min_pos.y, c.y)
		max_pos.x = maxf(max_pos.x, c.x)
		max_pos.y = maxf(max_pos.y, c.y)

	cell_size = (1.0 + maxf(union_smoothness, 0.0)) * max_radius
	if cell_size <= 0.0:
		# Degenerate (every radius clamps to the same non-positive value —
		# unreachable in practice, since radius is floored to >= 1.0 before it
		# reaches this class; kept for defensiveness).
		circles_texture = null
		tile_index_texture = null
		tile_circle_indices_texture = null
		return
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

	for i in circles.size():
		var cell := _cell_of(Vector2(circles[i].x, circles[i].y))
		if not _cells.has(cell):
			_cells[cell] = []
		(_cells[cell] as Array).append(i)

	_build_textures()


## Indices of every circle that can contribute at `world_pos`, in the SAME
## order the shader visits them: tiles in (dx, dy) scan order, each tile's
## circles in build (global-insertion) order. See the class docstring — this
## is the order any CPU-side fold must use to stay in lockstep with the GPU.
func gather_tile_order(world_pos: Vector2) -> Array:
	if _degenerate:
		var all: Array = []
		for i in _circles.size():
			all.append(i)
		return all
	var out: Array = []
	var centre := _cell_of(world_pos)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var bucket: Array = _cells.get(centre + Vector2i(dx, dy), [])
			out.append_array(bucket)
	return out


func get_circle(i: int) -> Vector4:
	return _circles[i]


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - grid_origin.x) / cell_size), floori((p.y - grid_origin.y) / cell_size))


func _build_textures() -> void:
	var circles_img := Image.create(maxi(circle_count, 1), 1, false, Image.FORMAT_RGBAF)
	for i in circle_count:
		var c: Vector4 = _circles[i]
		circles_img.set_pixel(i, 0, Color(c.x, c.y, c.z, c.w))
	circles_texture = ImageTexture.create_from_image(circles_img)

	var tile_index_img := Image.create(grid_cols, grid_rows, false, Image.FORMAT_RGF)
	var tile_indices_img := Image.create(maxi(circle_count, 1), 1, false, Image.FORMAT_RF)

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
