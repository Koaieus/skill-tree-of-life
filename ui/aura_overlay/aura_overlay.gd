@tool
class_name AuraOverlay
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")

## World-space "this entity lives here" wash. Renders a single big rect with
## a territory shader; one circle per owned SkillNode (grouped by owning
## entity) is passed as a uniform array, alongside one colour per owning
## entity. See aura.gdshader for the blend rules (same-entity union,
## cross-entity hard cut).

const _MAX_CIRCLES := 256
const _MAX_ENTITIES := 8

@export var enabled: bool = true:
	set(value):
		enabled = value
		_refresh()
@export var graph: Graph:
	set(value):
		graph = value
		_refresh()
@export var allocation_system: AllocationSystem:
	set(value):
		_disconnect_allocation()
		allocation_system = value
		_connect_allocation()
		_refresh()
@export_range(0.0, 1.0, 0.01) var intensity: float = 0.6:
	set(value):
		intensity = value
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"intensity", intensity)
@export_range(0.01, 1.0, 0.01) var falloff: float = 0.6:
	set(value):
		falloff = value
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"falloff", falloff)
## How far the aura reaches past a node's own visual radius.
@export var radius_multiplier: float = 1.5:
	set(value):
		radius_multiplier = value
		_refresh()
## World-space rect to paint. Should engulf the playable graph.
@export var bounds: Rect2 = Rect2(-3000, -2250, 6000, 4500)


func _ready() -> void:
	z_as_relative = false
	z_index = ZLayers.AURA
	if material is ShaderMaterial:
		var mat: ShaderMaterial = material
		mat.set_shader_parameter(&"intensity", intensity)
		mat.set_shader_parameter(&"falloff", falloff)
	if Engine.is_editor_hint():
		return
	_connect_allocation()
	if not Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.connect(_on_entity_died)
	_refresh()


func _draw() -> void:
	# Color is irrelevant — the shader writes COLOR directly.
	draw_rect(bounds, Color.WHITE)


func _refresh() -> void:
	visible = enabled
	if not visible or not is_inside_tree():
		return
	queue_redraw()
	if material == null or not material is ShaderMaterial:
		return
	var mat: ShaderMaterial = material
	if graph == null:
		mat.set_shader_parameter(&"circle_count", 0)
		mat.set_shader_parameter(&"entity_count", 0)
		return

	var owned_by_entity: Dictionary = {}
	for sn in graph.get_skill_nodes():
		var owner: Entity = sn.owned_by
		if owner == null or owner.is_dead:
			continue
		if not owned_by_entity.has(owner):
			owned_by_entity[owner] = []
		(owned_by_entity[owner] as Array).append(sn)

	var packed_circles: Array = []
	var packed_colors: Array = []
	var entity_idx := 0
	for owner in owned_by_entity:
		if entity_idx >= _MAX_ENTITIES:
			push_warning("AuraOverlay: more than %d owning entities; extras are not rendered" % _MAX_ENTITIES)
			break
		for sn in owned_by_entity[owner]:
			if packed_circles.size() >= _MAX_CIRCLES:
				break
			packed_circles.append(Vector4(
				sn.global_position.x, sn.global_position.y,
				sn.radius * radius_multiplier, float(entity_idx)
			))
		packed_colors.append((owner as Entity).color)
		entity_idx += 1

	var circle_count := packed_circles.size()
	var entity_count := packed_colors.size()
	while packed_circles.size() < _MAX_CIRCLES:
		packed_circles.append(Vector4.ZERO)
	while packed_colors.size() < _MAX_ENTITIES:
		packed_colors.append(Color(0.0, 0.0, 0.0, 0.0))

	mat.set_shader_parameter(&"circles", packed_circles)
	mat.set_shader_parameter(&"circle_count", circle_count)
	mat.set_shader_parameter(&"entity_colors", packed_colors)
	mat.set_shader_parameter(&"entity_count", entity_count)


func _on_entity_died(_entity: Entity) -> void:
	_refresh()


func _connect_allocation() -> void:
	if allocation_system == null:
		return
	if not allocation_system.allocated.is_connected(_on_ownership_changed):
		allocation_system.allocated.connect(_on_ownership_changed)
	if not allocation_system.deallocated.is_connected(_on_ownership_changed):
		allocation_system.deallocated.connect(_on_ownership_changed)
	if not allocation_system.force_deallocated.is_connected(_on_ownership_changed):
		allocation_system.force_deallocated.connect(_on_ownership_changed)


func _disconnect_allocation() -> void:
	if allocation_system == null:
		return
	if allocation_system.allocated.is_connected(_on_ownership_changed):
		allocation_system.allocated.disconnect(_on_ownership_changed)
	if allocation_system.deallocated.is_connected(_on_ownership_changed):
		allocation_system.deallocated.disconnect(_on_ownership_changed)
	if allocation_system.force_deallocated.is_connected(_on_ownership_changed):
		allocation_system.force_deallocated.disconnect(_on_ownership_changed)


func _on_ownership_changed(_node: SkillNode, _entity_arg: Variant = null, _extra: Variant = null) -> void:
	_refresh()
