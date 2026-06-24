@tool
class_name PoissonDiskSampler
extends RefCounted

## Bridson Poisson-disk sampling, bounded by a [ShapeMask]. Caller-supplied
## anchors are seeded first and respected during rejection, so starting
## locations always land and nothing crowds them.
##
## Returns points in graph-local space (centred on 0,0 — see ShapeMask).

const _K_TRIES := 30


static func sample(
		mask: ShapeMask,
		min_dist: float,
		max_points: int,
		anchors: Array[Vector2],
		rng: RandomNumberGenerator,
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if mask == null or min_dist <= 0.0:
		return out
	var bounds := mask.aabb()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return out

	var cell := min_dist / sqrt(2.0)
	var cols := int(ceil(bounds.size.x / cell))
	var rows := int(ceil(bounds.size.y / cell))
	var grid: Array = []
	grid.resize(cols * rows)
	for i in grid.size():
		grid[i] = -1

	var active: Array[int] = []

	var try_emit := func(p: Vector2) -> bool:
		if not mask.contains(p):
			return false
		if not _grid_ok(p, min_dist, bounds, cell, cols, rows, grid, out):
			return false
		var idx := out.size()
		out.append(p)
		var gx := int((p.x - bounds.position.x) / cell)
		var gy := int((p.y - bounds.position.y) / cell)
		grid[gy * cols + gx] = idx
		active.append(idx)
		return true

	for a in anchors:
		try_emit.call(a)

	if out.is_empty():
		# Seed the active list with a random valid point so generation can start.
		for _i in 64:
			var p := Vector2(
					rng.randf_range(bounds.position.x, bounds.end.x),
					rng.randf_range(bounds.position.y, bounds.end.y))
			if try_emit.call(p):
				break
		if out.is_empty():
			return out

	while not active.is_empty() and out.size() < max_points:
		var ai := rng.randi() % active.size()
		var origin: Vector2 = out[active[ai]]
		var placed := false
		for _t in _K_TRIES:
			var angle := rng.randf() * TAU
			var r := rng.randf_range(min_dist, min_dist * 2.0)
			var cand := origin + Vector2(cos(angle), sin(angle)) * r
			if try_emit.call(cand):
				placed = true
				if out.size() >= max_points:
					break
		if not placed:
			active.remove_at(ai)
	return out


static func _grid_ok(
		p: Vector2, min_dist: float, bounds: Rect2, cell: float,
		cols: int, rows: int, grid: Array, points: Array[Vector2]) -> bool:
	var gx := int((p.x - bounds.position.x) / cell)
	var gy := int((p.y - bounds.position.y) / cell)
	if gx < 0 or gy < 0 or gx >= cols or gy >= rows:
		return false
	var min_sq := min_dist * min_dist
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var nx := gx + dx
			var ny := gy + dy
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var idx: int = grid[ny * cols + nx]
			if idx == -1:
				continue
			if points[idx].distance_squared_to(p) < min_sq:
				return false
	return true
