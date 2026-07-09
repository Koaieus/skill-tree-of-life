class_name VisionSourceIndex
extends RefCounted

## Uniform-grid index over [method VisionSystem.get_vision_sources], built once
## per [code]FogOverlay._refresh[/code] and queried once per rendered element.
##
## [b]Why this exists.[/b] [code]FogOverlay._apply_per_element_dimming[/code]
## samples the fog darkness at every node and every edge midpoint, and each
## sample folded over [i]every[/i] vision source. That is O(elements × sources),
## and it runs per frame while any vision circle is animating (VisionSystem
## emits [signal VisionSystem.vision_render_tick] from [code]_process[/code]).
## Measured before this index: 16.8 ms per refresh at 150 sources / 300
## elements, 140 ms at 512 / 800. See #133.
##
## [b]Why the cull is exact, not an approximation.[/b] The fold is
## [code]m = field_smin(m, d, k)[/code]. Expand it for [code]d >= m + k[/code]:
## [code]h = clamp(0.5 + 0.5*(d - m)/k, 0, 1)[/code] hits 1, so the result is
## [code]mix(d, m, 1) - k*1*(1-1) == m[/code]. A source that far away does not
## contribute a small amount — it contributes [i]nothing[/i]. So dropping it
## changes no bit of the result, provided the fold visits distances in
## ascending order (see [method distances_near]).
##
## Every source that can matter has its centre within
## [code](1 + k) * max_radius[/code] of the query point, so a grid of that cell
## size answers any query from its 3×3 neighbourhood.

# Grid cell → PackedInt32Array of indices into `_sources`.
var _cells: Dictionary = {}
var _sources: Array = []
# Cell size, and the query reach it was derived from. Equal by construction:
# a point within `reach` of `p` cannot be more than one cell away from `p`.
var _reach: float = 0.0
# Set when the source set is degenerate (empty, or every radius non-positive).
# Queries then fall back to a linear scan, which is trivially correct.
var _degenerate: bool = true


## `union_smoothness` is the smin blend width `k`; it widens the reach, because
## a source up to `k` normalized units past the nearest one still perturbs the
## union.
func build(sources: Array, union_smoothness: float) -> void:
	_cells.clear()
	_sources = sources
	_degenerate = true
	if sources.is_empty():
		return

	var max_radius: float = 0.0
	for s in sources:
		max_radius = maxf(max_radius, _effective_radius(s))
	# `min_d <= 1` for any element the caller dims (it only dims *visible*
	# elements, which lie inside some circle). So a source matters only while
	# `d < 1 + k`, i.e. its centre is within `(1 + k) * its own radius` — and
	# `max_radius` bounds that over the whole set.
	_reach = (1.0 + maxf(union_smoothness, 0.0)) * max_radius
	if _reach <= 0.0:
		return
	_degenerate = false

	for i in sources.size():
		var cell := _cell_of(sources[i].pos)
		if not _cells.has(cell):
			_cells[cell] = PackedInt32Array()
		var bucket: PackedInt32Array = _cells[cell]
		bucket.append(i)
		_cells[cell] = bucket


## Normalized distances (`|p - centre| / radius`) to every source that can
## affect the fold at `world_pos`, sorted ascending.
##
## Ascending order is load-bearing, not a convenience. The fold's early-out
## ("stop once `d >= m + k`, since `m` only decreases and later `d`s only grow")
## is only sound on a sorted sequence — and sorting also makes the result
## independent of the source array's order, which it previously was not
## ([method VisionSystem.get_vision_sources] iterates a Dictionary).
func distances_near(world_pos: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _degenerate:
		for s in _sources:
			out.append(world_pos.distance_to(s.pos) / _effective_radius(s))
		out.sort()
		return out

	var centre := _cell_of(world_pos)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var bucket: PackedInt32Array = _cells.get(centre + Vector2i(dx, dy), PackedInt32Array())
			for i in bucket:
				var s = _sources[i]
				out.append(world_pos.distance_to(s.pos) / _effective_radius(s))
	out.sort()
	return out


## The `motion` of the source with the smallest true (un-smoothed) distance,
## mirroring the shader's `closest_motion`. 0.0 when nothing is in reach.
func closest_motion(world_pos: Vector2) -> float:
	var best_d: float = INF
	var best_motion: float = 0.0
	var candidates: PackedInt32Array = _candidates(world_pos)
	for i in candidates:
		var s = _sources[i]
		var d: float = world_pos.distance_to(s.pos) / _effective_radius(s)
		if d < best_d:
			best_d = d
			best_motion = s.get("motion", 0.0)
	return best_motion


func _candidates(world_pos: Vector2) -> PackedInt32Array:
	if _degenerate:
		var all := PackedInt32Array()
		for i in _sources.size():
			all.append(i)
		return all
	var out := PackedInt32Array()
	var centre := _cell_of(world_pos)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var bucket: PackedInt32Array = _cells.get(centre + Vector2i(dx, dy), PackedInt32Array())
			out.append_array(bucket)
	return out


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _reach), floori(p.y / _reach))


## Mirrors the shader's `max(c.z, 1.0)` — a zero-radius source would divide by
## zero and poison the fold with NaN.
static func _effective_radius(source) -> float:
	return maxf(source.radius, 1.0)
