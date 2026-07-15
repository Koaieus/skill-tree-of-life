class_name VisionSourceIndex
extends RefCounted

## Uniform-grid index over [method VisionSystem.get_vision_sources], built once
## per [code]FogOverlay._refresh[/code] and queried once per rendered element.
## Wraps [OverlayFieldTileIndex] — the same grid the fragment shader reads via
## data textures (see #177) — so the CPU dimming pass and the GPU fold walk
## the exact same candidate set in the exact same order.
##
## [b]Why this exists.[/b] [code]FogOverlay._apply_per_element_dimming[/code]
## samples the fog darkness at every node and every edge midpoint, and each
## sample folded over [i]every[/i] vision source. That is O(elements × sources),
## and it runs per frame while any vision circle is animating (VisionSystem
## emits [signal VisionSystem.vision_render_tick] from [code]_process[/code]).
## Measured before this index: 16.8 ms per refresh at 150 sources / 300
## elements, 140 ms at 512 / 800. See #133.
##
## [b]Order is tile-gather order, NOT ascending source index.[/b] Until #177
## this returned distances sorted back into global array order, to match a
## shader that looped every circle front-to-back. The tiled shader instead
## visits its own 3×3 tile neighbourhood — tiles in (dx, dy) scan order, each
## tile's circles in build (global-insertion) order — so this class now
## mirrors THAT traversal instead. See [OverlayFieldTileIndex]'s docstring for
## the measured drift this reorder introduces relative to the old pure-global
## order (0.0026, under the 1/255 = 0.0039 visible threshold).

var _tile_index := OverlayFieldTileIndex.new()
var _sources: Array = []


## `union_smoothness` is the smin blend width `k`; it widens the reach, because
## a source up to `k` normalized units past the nearest one still perturbs the
## union.
func build(sources: Array, union_smoothness: float) -> void:
	_sources = sources
	var circles: Array = []
	for s in sources:
		circles.append(Vector4(s.pos.x, s.pos.y, _effective_radius(s), s.get("motion", 0.0)))
	_tile_index.build(circles, union_smoothness)


## The tile grid + data textures this index built, for [FogOverlay] to upload
## to the shader. Only valid after [method build].
func tile_index() -> OverlayFieldTileIndex:
	return _tile_index


## Normalized distances (`|p - centre| / radius`) to every source that can
## affect the fold at `world_pos`, in [b]tile-gather order[/b] — see the class
## docstring. Folding in any other order measurably changes the result
## (`field_smin` is not associative): a node in the fade zone would then dim
## by a different amount than the fog the shader paints behind it.
func distances_near(world_pos: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in _tile_index.gather_tile_order(world_pos):
		var s = _sources[i]
		out.append(world_pos.distance_to(s.pos) / _effective_radius(s))
	return out


## The `motion` of the source with the smallest true (un-smoothed) distance,
## mirroring the shader's `closest_motion`. 0.0 when nothing is in reach.
func closest_motion(world_pos: Vector2) -> float:
	var best_d: float = INF
	var best_motion: float = 0.0
	for i in _tile_index.gather_tile_order(world_pos):
		var s = _sources[i]
		var d: float = world_pos.distance_to(s.pos) / _effective_radius(s)
		if d < best_d:
			best_d = d
			best_motion = s.get("motion", 0.0)
	return best_motion


## Mirrors the shader's `max(c.z, 1.0)` — a zero-radius source would divide by
## zero and poison the fold with NaN.
static func _effective_radius(source) -> float:
	return maxf(source.radius, 1.0)
