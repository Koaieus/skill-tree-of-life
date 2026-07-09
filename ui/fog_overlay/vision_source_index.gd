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
## [b]Why the cull is exact, not an approximation.[/b] `field_smin(a, b, k)`
## returns [code]b[/code] [i]identically[/i] when [code]b <= a - k[/code]: the
## blend factor [code]h = clamp(0.5 + 0.5*(b - a)/k, 0, 1)[/code] hits 0, so the
## result is [code]mix(b, a, 0) - k*0*(1-0) == b[/code]. Call that [i]erasure[/i]:
## folding in a distance at least `k` below the running minimum discards every
## contribution before it.
##
## `_apply_per_element_dimming` only samples elements it has already decided are
## [i]visible[/i], so some source has [code]d <= 1[/code] at the query point.
## Any source with [code]d >= 1 + k[/code] is therefore erased by that nearest
## one, whichever order the fold happens to reach them in — it contributes
## nothing, not a little. Dropping it changes no bit of the result.
##
## And a source can only reach [code]d < 1 + k[/code] if its centre is within
## [code](1 + k) * its own radius[/code], which [code]max_radius[/code] bounds
## over the whole set — so a grid of that cell size answers any query from its
## 3×3 neighbourhood.

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
## affect the fold at `world_pos`, in [b]ascending source-index order[/b].
##
## The order is load-bearing. `field_smin` is not perfectly associative, so the
## fold's result depends on the order it visits distances — and the fragment
## shader has no choice but to walk its uniform array front to back (distance is
## per-pixel; the GPU cannot sort). If the CPU folds in any other order, a node
## sitting in the fade zone dims by a different amount than the fog painted
## behind it. Measured drift for a value-sorted fold: 0.061, against a visible
## threshold of 1/255 = 0.0039.
##
## So: same order as `FogOverlay`'s packed uniform array, which is `_sources`.
func distances_near(world_pos: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var candidates := _candidates(world_pos)
	# Cells are visited in grid order, so the gathered indices are not in
	# source order until sorted. Sorting *indices* preserves the shader's
	# traversal; sorting *distances* would not.
	candidates.sort()
	for i in candidates:
		var s = _sources[i]
		out.append(world_pos.distance_to(s.pos) / _effective_radius(s))
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


## Indices of every source that can contribute at `world_pos`. Unordered.
func _candidates(world_pos: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _degenerate:
		for i in _sources.size():
			out.append(i)
		return out
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
