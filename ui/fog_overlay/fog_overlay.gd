@tool
class_name FogOverlay
extends Node2D

## World-space darkness layer driven by a [VisionSystem]. Renders a single
## big rect with a radial-cutout shader; vision circles are passed as a
## uniform array. Decoupled from VisionSystem's logic — remove this node
## from the scene and input gating still works, just no visible fog.
##
## [b]Intensity slider[/b] is the debug knob: 0 = invisible, 1 = full black.
## Falloff softens the circle edge.

const _MAX_CIRCLES := 256
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
## World-space rect to paint. Should engulf the playable graph; over-sizing
## costs nothing meaningful (one ColorRect draw, fragment cost is per-pixel
## but those pixels were already on screen).
@export var bounds: Rect2 = Rect2(-2000, -2000, 6000, 6000)


func _ready() -> void:
	_apply_shader_intensity()
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(&"falloff", falloff)
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
	queue_redraw()
	if material == null or not material is ShaderMaterial:
		return
	var mat: ShaderMaterial = material
	var sources: Array = vision_system.get_vision_sources() if vision_system != null else []
	var packed: Array = []
	for s in sources:
		packed.append(Vector4(s.pos.x, s.pos.y, s.radius, s.get("motion", 0.0)))
		if packed.size() >= _MAX_CIRCLES:
			break
	# Pad to MAX so the uniform array always has a defined length — Godot's
	# canvas_item shader needs the array fully populated even when unused
	# slots are skipped via the count guard.
	while packed.size() < _MAX_CIRCLES:
		packed.append(Vector4.ZERO)
	mat.set_shader_parameter(&"circles", packed)
	mat.set_shader_parameter(&"circle_count", min(sources.size(), _MAX_CIRCLES))
	_apply_per_element_dimming(sources)


## Lift visible nodes/edges above the fog overlay and modulate their alpha
## by the fog-darkness sampled at their CENTER (not per-fragment). Without
## this, the per-fragment fog gradient bisects any node sitting in the fade
## zone — half the disk reads clear, the other half pure black — and the
## same node appears DARKER than a sensed neighbour in pitch black (sensed
## elements already z-promote above the fog). Sensed elements are left to
## their own render path (BaseCircle/Edge draw at a fixed sensed alpha).
func _apply_per_element_dimming(sources: Array) -> void:
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
			var dark := _sample_dark(n.global_position, sources)
			n.modulate.a = clamp(1.0 - dark, _VISIBLE_DIM_FLOOR, 1.0)
			n.z_as_relative = false
			n.z_index = 1001
		else:
			# Fully hidden: back to default z so the fog at z=1000 covers it.
			n.modulate.a = 1.0
			n.z_as_relative = true
			n.z_index = 0
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
			var dark := _sample_dark(mid, sources)
			e.modulate.a = clamp(1.0 - dark, _VISIBLE_DIM_FLOOR, 1.0)
			e.z_as_relative = false
			e.z_index = 1001
		else:
			e.modulate.a = 1.0
			e.z_as_relative = true
			e.z_index = 0


## Mirrors the shader's darkness math (fog.gdshader): linear ramp 0 → 1
## across the fade zone [(1-falloff)·r .. r], pinned at 1 beyond. Sampling
## once per element at its center gives uniform per-element dimming.
func _sample_dark(world_pos: Vector2, sources: Array) -> float:
	if sources.is_empty():
		return 1.0
	var min_d: float = INF
	for s in sources:
		var pos: Vector2 = s.pos
		var r: float = max(s.radius, 1.0)
		var d: float = world_pos.distance_to(pos) / r
		if d < min_d:
			min_d = d
	var fade_start: float = 1.0 - falloff
	return clamp((min_d - fade_start) / max(falloff, 1e-4), 0.0, 1.0)


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
