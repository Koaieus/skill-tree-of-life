@tool
class_name AuraOverlay
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")

## World-space "this entity lives here" wash. Renders a single big rect with
## a territory shader over the entity's OWNED INDUCED SUBGRAPH (#898): one
## rounded cone per owned SkillNode (degenerate, `A == B` — a disc) and one
## per edge whose two endpoints share an owner (a rectangle along the edge,
## tapering to a trapezoid when the stake radii differ), each tagged with the
## owning entity's index, alongside one colour per owning entity. A
## half-owned edge, or one between two different owners, draws nothing for
## either (#140 decision 3). See aura.gdshader for the blend rules
## (same-entity smooth union, cross-entity hard cut).

## Sanity ceiling on PRIMITIVES (discs + edge cones), not an array bound
## (#177 moved storage to data textures — see OverlayFieldTileIndex).
## Loud-or-none guard against a pathological count silently eating GPU
## memory.
const _MAX_CIRCLES := 20000
## `entity_colors` stays a plain uniform array — genuinely small (one Color
## per owning entity) — so this IS a real array bound. Target scale is 20
## entities; 32 leaves headroom.
const _MAX_ENTITIES := 32

# Truncation is loud, but only once per onset — _refresh runs on every
# allocating frame, and a warning per refresh would bury the log.
var _warned_circle_overflow: bool = false
# Signal-driven refreshes coalesce to one walk per frame: a synchronous burst
# (a forced-dealloc cascade, a concede strip) would otherwise pay a full
# O(nodes + edges) rebuild per landing. The deferred flush runs before the
# frame draws, so each frame's landings still paint in that frame.
var _refresh_deferred := DeferredOnce.new(_refresh)
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
## Dumbbell knobs (#140 decision 8). An edge cone's end radii are the two aura
## disc radii scaled by `w = edge_width / (1 + L / edge_slack_length)`, `L`
## the edge length in px; the `smin` union with the full discs makes the
## neck. `1.0` with an INF slack is the plain capsule tangent to both discs.
@export_range(0.01, 1.0, 0.01) var edge_width: float = 0.6:
	set(value):
		edge_width = value
		_refresh()
## Longer edges pinch more: at `L == edge_slack_length` the cone is half
## `edge_width`. `INF` disables the pinch.
@export var edge_slack_length: float = 300.0:
	set(value):
		edge_slack_length = value
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
		# #504: ownership as modelled IS ownership as drawn — the cascade
		# mutates one landing at a time on the beat clock, so this refresh
		# already tracks it a step at a time.
		var _owner: Entity = sn.owned_by
		if _owner == null or _owner.is_dead:
			continue
		if not owned_by_entity.has(_owner):
			owned_by_entity[_owner] = []
		(owned_by_entity[_owner] as Array).append(sn)

	var total_owned := 0
	for _owner in owned_by_entity:
		total_owned += (owned_by_entity[_owner] as Array).size()

	# Two texels per primitive: (ax, ay, ra, entity_idx), (bx, by, rb, 0).
	var packed_cones: Array = []
	var packed_colors: Array = []
	var entity_index: Dictionary = {}
	var entity_idx := 0
	for _owner in owned_by_entity:
		if entity_idx >= _MAX_ENTITIES:
			_warn_once(&"_warned_entity_overflow",
				"AuraOverlay: %d owning entities exceeds the %d-colour cap; the extras render no aura."
					% [owned_by_entity.size(), _MAX_ENTITIES])
			break
		entity_index[_owner] = entity_idx
		# Every owned node ships as a degenerate cone regardless of degree —
		# an isolated owned node must not vanish (#140 decision 6).
		for sn in owned_by_entity[_owner]:
			if packed_cones.size() >= 2 * _MAX_CIRCLES:
				break
			var r: float = sn.radius * radius_multiplier
			packed_cones.append(Vector4(sn.global_position.x, sn.global_position.y, r, float(entity_idx)))
			packed_cones.append(Vector4(sn.global_position.x, sn.global_position.y, r, 0.0))
		packed_colors.append(Emissive.tint_damped((_owner as Entity).color, Emissive.INERT))
		entity_idx += 1

	# Edges of the owned induced subgraph: both endpoints owned by the SAME
	# entity (`owned_by` identity, never ownership_bit — this is "same entity",
	# not "mine"). `entity_index.has` also folds in null / dead / over-cap
	# owners, which never made the map.
	var total_edges := 0
	for edge in graph.get_edges():
		var a: SkillNode = edge.from
		var b: SkillNode = edge.to
		# A self-loop would emit a second, smaller degenerate on the same node,
		# and field_smin is not idempotent — it would deepen the disc.
		if a == null or b == null or a == b:
			continue
		if a.owned_by != b.owned_by or not entity_index.has(a.owned_by):
			continue
		total_edges += 1
		if packed_cones.size() >= 2 * _MAX_CIRCLES:
			continue
		var idx: int = entity_index[a.owned_by]
		var w := _edge_width_for(a.global_position.distance_to(b.global_position))
		packed_cones.append(Vector4(a.global_position.x, a.global_position.y,
			a.radius * radius_multiplier * w, float(idx)))
		packed_cones.append(Vector4(b.global_position.x, b.global_position.y,
			b.radius * radius_multiplier * w, 0.0))

	# Truncation silently deletes territory from the board — whatever is packed
	# last simply stops rendering. Never let that pass unremarked.
	var total_primitives := total_owned + total_edges
	if total_primitives > _MAX_CIRCLES:
		_warn_once(&"_warned_circle_overflow",
			"AuraOverlay: %d aura primitives (%d owned nodes + %d owned edges) exceeds the %d cap; %d render no aura. See #133."
				% [total_primitives, total_owned, total_edges, _MAX_CIRCLES, total_primitives - _MAX_CIRCLES])
	else:
		_warned_circle_overflow = false

	set_cones(packed_cones, packed_colors)


## Decision 8's dumbbell factor: `edge_width / (1 + L / edge_slack_length)`.
## An INF slack makes the quotient 0, i.e. plain `edge_width` — no special case.
func _edge_width_for(edge_length: float) -> float:
	return edge_width / (1.0 + edge_length / edge_slack_length)


## Upload a disc-only territory field directly. `circles` are unpadded
## `Vector4(world_x, world_y, radius, entity_index)`; `colors` are unpadded, one
## per entity, indexed by that `entity_index`. Each circle becomes a degenerate
## cone — the render path is [method set_cones]'s; this is the disc-shaped
## door onto it (the verify scene's disc case, the caps test).
func set_field(circles: Array, colors: Array) -> void:
	var cones: Array = []
	for c in circles.slice(0, mini(circles.size(), _MAX_CIRCLES)):
		cones.append(c)
		cones.append(Vector4(c.x, c.y, c.z, 0.0))
	set_cones(cones, colors)


## Upload a territory field of rounded cones. `cones` is `2 * n` unpadded
## texels, `(ax, ay, ra, entity_index)` then `(bx, by, rb, 0)` per primitive —
## exactly OverlayFieldTileIndex.build_cones' layout; `colors` are unpadded,
## one per entity, indexed by that `entity_index`.
##
## Split out from [method _refresh] so the render path can be driven without a
## live Graph — see `scenes/overlay_perf_harness.gd`, which must exercise the
## same entry point the game does for its numbers to mean anything.
func set_cones(cones: Array, colors: Array) -> void:
	if material == null or not material is ShaderMaterial:
		return
	var mat: ShaderMaterial = material
	var primitive_count := mini(cones.size() / 2, _MAX_CIRCLES)
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

	# Primitives go through the world-space tile index (#177, cones #897)
	# instead of a fixed-size uniform array — see OverlayFieldTileIndex. The
	# uniform names still say "circle": `circles_tex` carries the 2-texel
	# primitives texture and `circle_count` the primitive count.
	_tile_index.build_cones(cones.slice(0, primitive_count * 2), union_smoothness)
	mat.set_shader_parameter(&"circle_count", _tile_index.primitive_count)
	mat.set_shader_parameter(&"grid_origin", _tile_index.grid_origin)
	mat.set_shader_parameter(&"cell_size", _tile_index.cell_size)
	mat.set_shader_parameter(&"grid_cols", _tile_index.grid_cols)
	mat.set_shader_parameter(&"grid_rows", _tile_index.grid_rows)
	mat.set_shader_parameter(&"circles_tex", _tile_index.primitives_texture)
	mat.set_shader_parameter(&"tile_index_tex", _tile_index.tile_index_texture)
	mat.set_shader_parameter(&"tile_indices_tex", _tile_index.tile_circle_indices_texture)
	mat.set_shader_parameter(&"entity_colors", padded_colors)
	mat.set_shader_parameter(&"entity_count", entity_count)


## Warn on the rising edge only. `_refresh` runs on every allocating frame, so an
## unguarded push_warning would emit once per node for the rest of the match.
func _warn_once(flag: StringName, message: String) -> void:
	if get(flag):
		return
	set(flag, true)
	push_warning(message)


func _on_entity_died(_entity: Entity) -> void:
	_refresh_deferred.request()


func _connect_allocation() -> void:
	# Export setters fire during scene deserialization too — including a
	# non-playing editor load, where an injected system resolves to a bare
	# `Node` with no signals on it. Guard here rather than only in `_ready()`,
	# since the setters call this directly (see
	# `.claude/rules/gdscript-pitfalls.md`).
	if Engine.is_editor_hint():
		return
	if allocation_system != null:
		if not allocation_system.allocated.is_connected(_on_ownership_changed):
			allocation_system.allocated.connect(_on_ownership_changed)
		if not allocation_system.deallocated.is_connected(_on_ownership_changed):
			allocation_system.deallocated.connect(_on_ownership_changed)
		# #504: forced-dealloc territory loss (combat cascade, entity-death
		# strip, or a standalone force-dealloc) refreshes off the mutation
		# itself. That fires at the landing's own `arrival_time`, so the
		# territory paint keeps step with the node paint for free — one
		# handler, every case.
		if not allocation_system.force_deallocated.is_connected(_on_ownership_changed):
			allocation_system.force_deallocated.connect(_on_ownership_changed)


func _disconnect_allocation() -> void:
	if Engine.is_editor_hint():
		return
	if allocation_system != null:
		if allocation_system.allocated.is_connected(_on_ownership_changed):
			allocation_system.allocated.disconnect(_on_ownership_changed)
		if allocation_system.deallocated.is_connected(_on_ownership_changed):
			allocation_system.deallocated.disconnect(_on_ownership_changed)
		if allocation_system.force_deallocated.is_connected(_on_ownership_changed):
			allocation_system.force_deallocated.disconnect(_on_ownership_changed)


## `_refresh()` re-reads the whole ownership model, so one refresh per frame
## is correct even mid-cascade: it paints the territory as it stands at the end
## of that frame's landings.
func _on_ownership_changed(_node: SkillNode, _entity_arg: Variant = null, _extra: Variant = null) -> void:
	_refresh_deferred.request()
