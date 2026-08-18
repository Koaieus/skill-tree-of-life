@tool
class_name AuraOverlay
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")

## World-space "this entity lives here" wash. Renders a single big rect with
## a territory shader; one circle per owned SkillNode (grouped by owning
## entity) is passed as a uniform array, alongside one colour per owning
## entity. See aura.gdshader for the blend rules (same-entity union,
## cross-entity hard cut).

## Sanity ceiling, not an array bound (#177 moved circle storage to data
## textures — see OverlayFieldTileIndex). Loud-or-none guard against a
## pathological owned-node count silently eating GPU memory.
const _MAX_CIRCLES := 20000
## `entity_colors` stays a plain uniform array — genuinely small (one Color
## per owning entity) — so this IS a real array bound. Target scale is 20
## entities; 32 leaves headroom.
const _MAX_ENTITIES := 32

# Truncation is loud, but only once per onset — _refresh runs on every
# allocation, and a warning per node would bury the log.
var _warned_circle_overflow: bool = false
var _tile_index := OverlayFieldTileIndex.new()

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
## Blend width of the same-entity smooth union, in normalized-distance units.
## Cross-entity boundaries stay a hard cut regardless.
@export_range(0.0, 0.5, 0.01) var union_smoothness: float = 0.12:
	set(value):
		union_smoothness = value
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"union_smoothness", union_smoothness)
## How far the aura reaches past a node's own visual radius.
@export var radius_multiplier: float = 1.5:
	set(value):
		radius_multiplier = value
		_refresh()
## World-space rect to paint. Should engulf the playable graph. GameRoot
## updates this live as the camera's zoom-scaled pan limit changes
## (GraphCamera.bounds_changed), so the setter must redraw rather than wait
## for the next allocation-driven refresh.
@export var bounds: Rect2 = Rect2(-3000, -2250, 6000, 4500):
	set(value):
		bounds = value
		queue_redraw()


func _ready() -> void:
	z_as_relative = false
	z_index = ZLayers.AURA
	if material is ShaderMaterial:
		var mat: ShaderMaterial = material
		mat.set_shader_parameter(&"intensity", intensity)
		mat.set_shader_parameter(&"falloff", falloff)
		mat.set_shader_parameter(&"union_smoothness", union_smoothness)
	_refresh.call_deferred()
	if Engine.is_editor_hint():
		return
	_connect_allocation()
	if not Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.connect(_on_entity_died)


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
		# Presentation clock (#483): ownership as DRAWN, not as modelled. A node
		# mid-reveal is already `owned_by == null`, and reading that would snap
		# the defender's whole cascade away on the first revealed node instead
		# of one stagger slot at a time.
		var _owner: Entity = sn.get_shown_owner()
		if _owner == null or _owner.is_dead:
			continue
		if not owned_by_entity.has(_owner):
			owned_by_entity[_owner] = []
		(owned_by_entity[_owner] as Array).append(sn)

	var total_owned := 0
	for _owner in owned_by_entity:
		total_owned += (owned_by_entity[_owner] as Array).size()

	var packed_circles: Array = []
	var packed_colors: Array = []
	var entity_idx := 0
	for _owner in owned_by_entity:
		if entity_idx >= _MAX_ENTITIES:
			_warn_once(&"_warned_entity_overflow",
				"AuraOverlay: %d owning entities exceeds the %d-colour cap; the extras render no aura."
					% [owned_by_entity.size(), _MAX_ENTITIES])
			break
		for sn in owned_by_entity[_owner]:
			if packed_circles.size() >= _MAX_CIRCLES:
				break
			packed_circles.append(Vector4(
				sn.global_position.x, sn.global_position.y,
				sn.radius * radius_multiplier, float(entity_idx)
			))
		packed_colors.append((_owner as Entity).color)
		entity_idx += 1

	# Truncation silently deletes territory from the board — whichever entity is
	# packed last simply stops rendering. Never let that pass unremarked.
	if total_owned > _MAX_CIRCLES:
		_warn_once(&"_warned_circle_overflow",
			"AuraOverlay: %d owned nodes exceeds the %d-circle cap; %d nodes render no aura. See #133."
				% [total_owned, _MAX_CIRCLES, total_owned - _MAX_CIRCLES])
	else:
		_warned_circle_overflow = false

	set_field(packed_circles, packed_colors)


## Upload a territory field directly. `circles` are unpadded
## `Vector4(world_x, world_y, radius, entity_index)`; `colors` are unpadded, one
## per entity, indexed by that `entity_index`.
##
## Split out from [method _refresh] so the render path can be driven without a
## live Graph — see `scenes/overlay_perf_harness.gd`, which must exercise the
## same entry point the game does for its numbers to mean anything.
func set_field(circles: Array, colors: Array) -> void:
	if material == null or not material is ShaderMaterial:
		return
	var mat: ShaderMaterial = material
	var circle_count := mini(circles.size(), _MAX_CIRCLES)
	var entity_count := mini(colors.size(), _MAX_ENTITIES)
	# `entity_colors` stays a plain uniform array — small, so pad explicitly
	# rather than resize()-then-patch: resize() fills a *typed* array with the
	# type's default (Color(0,0,0,1) — opaque black), not null, so a
	# null-check pass would silently leave opaque padding behind.
	var padded_colors: Array = []
	padded_colors.resize(_MAX_ENTITIES)
	padded_colors.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i in entity_count:
		padded_colors[i] = colors[i]

	# Circles go through the world-space tile index (#177) instead of a
	# fixed-size uniform array — see OverlayFieldTileIndex.
	_tile_index.build(circles.slice(0, circle_count), union_smoothness)
	mat.set_shader_parameter(&"circle_count", _tile_index.circle_count)
	mat.set_shader_parameter(&"grid_origin", _tile_index.grid_origin)
	mat.set_shader_parameter(&"cell_size", _tile_index.cell_size)
	mat.set_shader_parameter(&"grid_cols", _tile_index.grid_cols)
	mat.set_shader_parameter(&"grid_rows", _tile_index.grid_rows)
	mat.set_shader_parameter(&"circles_tex", _tile_index.circles_texture)
	mat.set_shader_parameter(&"tile_index_tex", _tile_index.tile_index_texture)
	mat.set_shader_parameter(&"tile_indices_tex", _tile_index.tile_circle_indices_texture)
	mat.set_shader_parameter(&"entity_colors", padded_colors)
	mat.set_shader_parameter(&"entity_count", entity_count)


## Warn on the rising edge only. `_refresh` runs on every allocation, so an
## unguarded push_warning would emit once per node for the rest of the match.
func _warn_once(flag: StringName, message: String) -> void:
	if get(flag):
		return
	set(flag, true)
	push_warning(message)


func _on_entity_died(_entity: Entity) -> void:
	_refresh()


func _connect_allocation() -> void:
	if allocation_system == null:
		return
	if not allocation_system.allocated.is_connected(_on_ownership_changed):
		allocation_system.allocated.connect(_on_ownership_changed)
	if not allocation_system.deallocated.is_connected(_on_ownership_changed):
		allocation_system.deallocated.connect(_on_ownership_changed)
	if not allocation_system.force_deallocated.is_connected(_on_force_deallocated):
		allocation_system.force_deallocated.connect(_on_force_deallocated)
	# #483: a node whose territory loss is being revealed on the presentation
	# clock refreshes the aura at its reveal, not at its model mutation.
	if not Events.node_death_shown.is_connected(_on_ownership_changed):
		Events.node_death_shown.connect(_on_ownership_changed)


func _disconnect_allocation() -> void:
	if allocation_system == null:
		return
	if allocation_system.allocated.is_connected(_on_ownership_changed):
		allocation_system.allocated.disconnect(_on_ownership_changed)
	if allocation_system.deallocated.is_connected(_on_ownership_changed):
		allocation_system.deallocated.disconnect(_on_ownership_changed)
	if allocation_system.force_deallocated.is_connected(_on_force_deallocated):
		allocation_system.force_deallocated.disconnect(_on_force_deallocated)
	if Events.node_death_shown.is_connected(_on_ownership_changed):
		Events.node_death_shown.disconnect(_on_ownership_changed)


func _on_ownership_changed(_node: SkillNode, _entity_arg: Variant = null, _extra: Variant = null) -> void:
	_refresh()


## Forced dealloc splits two ways (#483). Combat territory loss is withheld:
## the node is holding its paint until the killing hit's VFX lands (direct hit)
## or until its slot in the cascade ripple (islanded neighbours), and
## `Events.node_death_shown` refreshes us then. Everything else — the entity-
## death strip, sandbox drivers — has no VFX to wait on and refreshes now.
##
## `_refresh()` re-reads the whole ownership model, so a refresh per revealed
## node is correct even mid-cascade: each one paints the territory as it stands
## at that beat.
func _on_force_deallocated(node: SkillNode, _previous_owner: Entity = null) -> void:
	if node != null and node.presentation_hold:
		return
	_refresh()
