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
	visible = vision_system == null or vision_system.should_render_fog()
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
