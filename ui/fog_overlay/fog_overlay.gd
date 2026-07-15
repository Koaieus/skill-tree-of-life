@tool
class_name FogOverlay
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")

## World-space darkness layer driven by a [VisionSystem]. Renders a single
## big rect with a radial-cutout shader; vision circles are passed as a
## uniform array. Decoupled from VisionSystem's logic — remove this node
## from the scene and input gating still works, just no visible fog.
##
## [b]Intensity slider[/b] is the debug knob: 0 = invisible, 1 = full black.
## Falloff softens the circle edge.

## Uniform-array bound, mirrored by `MAX_CIRCLES` in fog.gdshader. A *memory*
## bound, not a cost: the fragment loop breaks at `circle_count`, so an unused
## slot costs nothing per pixel. 512 vec4 ≈ 8KB of uniform storage.
const _MAX_CIRCLES := 512

# Truncation is loud, but only on the rising edge — _refresh runs on every
# vision tick, and a warning per frame would bury the log.
var _warned_overflow: bool = false
# Spatial index over the current vision sources, rebuilt each _refresh. Turns
# the per-element dimming pass from O(elements × sources) into O(elements).
var _source_index := VisionSourceIndex.new()
# Visible elements in the fade zone dim toward this floor instead of being
# bisected by the per-fragment fog gradient. Matches the sensed-outline
# alpha so a node transitioning visible → sensed has no brightness jump.
const _VISIBLE_DIM_FLOOR := 0.30

@export var enabled: bool = true

@export var vision_system: VisionSystem:
	set(value):
		_disconnect_vision()
		vision_system = value
		_connect_vision()
		_refresh()
@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0:
	set(value):
		intensity = value
		_apply_shader_intensity()
@export_range(0.0, 1.0, 0.01) var falloff: float = 0.25:
	set(value):
		falloff = value
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"falloff", falloff)
## Blend width of the smooth union between overlapping vision circles, in
## normalized-distance units. 0 = plain min(), which creases along each seam
## and reads as a band. Also feeds `_sample_dark`, so it must reach the shader.
@export_range(0.0, 0.5, 0.01) var union_smoothness: float = 0.12:
	set(value):
		union_smoothness = value
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"union_smoothness", union_smoothness)
## World-space rect to paint. Should engulf the playable graph; over-sizing
## costs nothing meaningful (one ColorRect draw, fragment cost is per-pixel
## but those pixels were already on screen).
@export var bounds: Rect2 = Rect2(-2000, -2000, 6000, 6000)


func _ready() -> void:
	_apply_shader_intensity()
	if material is ShaderMaterial:
		var mat: ShaderMaterial = material
		mat.set_shader_parameter(&"falloff", falloff)
		mat.set_shader_parameter(&"union_smoothness", union_smoothness)
	_connect_vision()
	_refresh()


func _draw() -> void:
	# Color is irrelevant — the shader writes COLOR directly.
	draw_rect(bounds, Color.WHITE)


func _refresh() -> void:
	# Hide entirely when the system says no fog is meaningful (e.g. inert
	# OFF mode). Avoids the shader's "zero circles → fully dark" default
	# kicking in and saves the fullscreen fragment pass.
	visible = enabled and (vision_system == null or vision_system.should_render_fog())
	if not visible:
		return
	set_sources(vision_system.get_vision_sources() if vision_system != null else [])


## Upload a vision-source set and re-dim the elements sitting in it. Each entry:
## `{ pos: Vector2, radius: float, motion: float }`, matching
## [method VisionSystem.get_vision_sources].
##
## Split out from [method _refresh] so the render path can be driven without a
## live VisionSystem — see `scenes/overlay_perf_harness.gd`, which must exercise
## the same entry point the game does for its numbers to mean anything.
func set_sources(sources: Array) -> void:
	queue_redraw()
	if material == null or not material is ShaderMaterial:
		return
	var mat: ShaderMaterial = material
	# Truncation here is worse than dropping a circle: `_apply_per_element_dimming`
	# reads the FULL list, so a node lit by a dropped circle would render bright
	# against fog the shader still paints black. Clamp both to the same set.
	if sources.size() > _MAX_CIRCLES:
		_warn_once("FogOverlay: %d vision sources exceeds the %d-circle cap; %d are not rendered and the graph will look wrong. See #133."
			% [sources.size(), _MAX_CIRCLES, sources.size() - _MAX_CIRCLES])
		sources = sources.slice(0, _MAX_CIRCLES)
	else:
		_warned_overflow = false

	var packed: Array = []
	for s in sources:
		packed.append(Vector4(s.pos.x, s.pos.y, s.radius, s.get("motion", 0.0)))
	# Pad to MAX so the uniform array always has a defined length — Godot's
	# canvas_item shader needs the array fully populated even when unused
	# slots are skipped via the count guard.
	while packed.size() < _MAX_CIRCLES:
		packed.append(Vector4.ZERO)
	mat.set_shader_parameter(&"circles", packed)
	mat.set_shader_parameter(&"circle_count", sources.size())
	# Built once per refresh, queried once per element. Without it the dimming
	# pass below is O(elements × sources) and runs every frame while circles
	# animate — 16.8ms at 150 sources / 300 elements. See #133.
	_source_index.build(sources, union_smoothness)
	_apply_per_element_dimming()


## Lift visible nodes/edges above the fog overlay and modulate their alpha
## by the fog-darkness sampled at their CENTER (not per-fragment). Without
## this, the per-fragment fog gradient bisects any node sitting in the fade
## zone — half the disk reads clear, the other half pure black — and the
## same node appears DARKER than a sensed neighbour in pitch black (sensed
## elements already z-promote above the fog). Sensed elements are left to
## their own render path (BaseCircle/Edge draw at a fixed sensed alpha).
func _apply_per_element_dimming() -> void:
	if vision_system == null or vision_system.graph == null:
		return
	var graph := vision_system.graph
	for n in graph.get_skill_nodes():
		if vision_system.is_sensed(n):
			# Sensed path: SkillNode already z-promotes; keep modulate
			# neutral so BaseCircle's fixed-alpha outline reads through.
			n.modulate.a = 1.0
			continue
		if vision_system.is_visible(n):
			var dark := _dark_from_distances(_source_index.distances_near(n.global_position))
			n.modulate.a = clamp(1.0 - dark, _VISIBLE_DIM_FLOOR, 1.0)
			n.z_as_relative = false
			n.z_index = ZLayers.GRAPH_DEFAULT + ZLayers.SENSED
		else:
			# Fully hidden: back to default z so the fog at z=FOG covers it.
			n.modulate.a = 1.0
			n.z_as_relative = true
			n.z_index = ZLayers.GRAPH_DEFAULT
	for e in graph.get_edges():
		if e.sensed:
			e.modulate.a = 1.0
			continue
		if e.from == null or e.to == null:
			continue
		var from_vis: bool = vision_system.is_visible(e.from)
		var to_vis: bool = vision_system.is_visible(e.to)
		if from_vis and to_vis:
			var mid: Vector2 = (e.from.global_position + e.to.global_position) * 0.5
			var dark := _dark_from_distances(_source_index.distances_near(mid))
			e.modulate.a = clamp(1.0 - dark, _VISIBLE_DIM_FLOOR, 1.0)
			e.z_as_relative = false
			e.z_index = ZLayers.EDGE + ZLayers.SENSED
		else:
			e.modulate.a = 1.0
			e.z_as_relative = true
			e.z_index = ZLayers.EDGE


## Mirrors the shader's darkness math (fog.gdshader): smooth union of the
## circle fields, then a smoothstep ramp 0 → 1 across the fade zone
## [(1-falloff)·r .. r], pinned at 1 beyond. Sampling once per element at its
## center gives uniform per-element dimming. Keep in lockstep with the shader
## — a mismatch makes a node's dimming disagree with the fog behind it.
##
## Reference implementation: folds the whole source set. `_apply_per_element_dimming`
## uses the indexed path instead, which is required to agree with this one
## (test_vision_source_index.gd pins that).
func _sample_dark(world_pos: Vector2, sources: Array) -> float:
	var ds := PackedFloat32Array()
	for s in sources:
		ds.append(world_pos.distance_to(s.pos) / max(s.radius, 1.0))
	return _dark_from_distances(ds)


## Fold normalized distances into a darkness in [0,1].
##
## `distances` must arrive in the same order the shader walks its `circles`
## uniform array. `field_smin` is not perfectly associative, so a different
## order gives a different answer — and the shader cannot reorder, because
## distance is per-pixel. Folding by ascending distance instead drifts by up to
## 0.061, against a visible threshold of 1/255; the node would then dim by a
## different amount than the fog painted behind it.
func _dark_from_distances(distances: PackedFloat32Array) -> float:
	if distances.is_empty():
		return 1.0
	# Finite sentinel, matching the shader. INF would make `lerp` produce
	# INF * 0.0 == NaN on the first fold.
	var min_d: float = 1e9
	for d in distances:
		min_d = _smin(min_d, d, union_smoothness)
	var fade_start: float = 1.0 - max(falloff, 1e-4)
	return smoothstep(fade_start, 1.0, min_d)


func _warn_once(message: String) -> void:
	if _warned_overflow:
		return
	_warned_overflow = true
	push_warning(message)


## Polynomial smooth-minimum. GDScript twin of `field_smin` in
## res://ui/overlay_field.gdshaderinc.
func _smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return min(a, b)
	var h: float = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerp(b, a, h) - k * h * (1.0 - h)


func _apply_shader_intensity() -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(&"intensity", intensity)


func _connect_vision() -> void:
	if vision_system == null:
		return
	if not vision_system.visibility_changed.is_connected(_refresh):
		vision_system.visibility_changed.connect(_refresh)
	if not vision_system.vision_render_tick.is_connected(_refresh):
		vision_system.vision_render_tick.connect(_refresh)


func _disconnect_vision() -> void:
	if vision_system == null:
		return
	if vision_system.visibility_changed.is_connected(_refresh):
		vision_system.visibility_changed.disconnect(_refresh)
	if vision_system.vision_render_tick.is_connected(_refresh):
		vision_system.vision_render_tick.disconnect(_refresh)
