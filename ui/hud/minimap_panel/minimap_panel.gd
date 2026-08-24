@tool
class_name MinimapPanel
extends MarginContainer

## Bottom-left HUD cluster (#453) — the whole board at a fixed scale, with fog,
## a live viewport outline, and click/drag to move the camera.
##
## [b]Three layers, split by redraw cadence[/b], which is the entire
## performance story at 500–2500 SkillNodes:
##   - [MinimapGraphLayer] — dots + edges. Rebuilt on topology/ownership
##     change only, and drawn in two batched calls (see that class).
##   - `FogLayer` — a ColorRect running `minimap_fog.gdshader`, which samples
##     the same GLOBAL vision field `FogOverlay` writes each vision tick. Zero
##     CPU: the minimap asks [VisionSystem] nothing, per node or otherwise.
##   - [MinimapViewportRectLayer] — the outline. The only thing that moves with
##     the camera, and the only thing a pan invalidates.
##
## [b]Extent[/b] is the graph AABB grown by the camera's zoom==1.0 pan margin —
## i.e. exactly [member GraphCamera]'s effective bounds at zoom 1.0, but FIXED.
## Following `bounds_changed` instead would be equally correct and is a one-line
## change ([method _refit]), but it rescales the whole map on every zoom step,
## so the board breathes underneath an outline that is itself already resizing.
## One of the two has to hold still, and it should be the board.
##
## v0 deliberately stops short of: sensed-only blips, archetype fill +
## ownership ring, per-entity territory boxes, combat pings, and minimap zoom
## levels. Each is an added layer or a swapped colour helper, not a rewrite —
## see the class docs on the pieces they'd touch.

## Colour of a node nobody owns. Dim on purpose: the map's job is "where is
## everyone", and unowned nodes are the ground that question is asked against.
@export var neutral_node_color: Color = Color(0.42, 0.47, 0.60, 0.55)
## Colour of an edge between two unowned nodes. Fainter still than the dots —
## at hairline width a full-strength mesh reads as noise, not as topology.
@export var neutral_edge_color: Color = Color(0.36, 0.41, 0.54, 0.30)
@export var edge_width: float = 1.0
@export var dot_size: float = 2.0

@onready var map_area: Control = %MapArea
@onready var graph_layer: MinimapGraphLayer = %GraphLayer
@onready var fog_layer: ColorRect = %FogLayer
@onready var viewport_rect_layer: MinimapViewportRectLayer = %ViewportRectLayer

var _graph: Graph
var _camera: GraphCamera

## Every connection made in [method bind], released as a unit. No `set_player`
## in v0 — nothing here is player-keyed — but a later blip layer keyed to the
## viewing hero will want this seam, and it costs one line to leave open.
var _binds := BindScope.new()

## World rect the map covers — the letterboxed graph AABB + margin.
var _world_bounds: Rect2 = Rect2()
## World rect the FOG quad covers: [member _world_bounds] expanded to the map
## area's aspect. Not the same rect, and the difference is load-bearing — `UV`
## in the fog shader spans the full-bleed ColorRect, so feeding it the
## letterboxed rect offsets the fog by exactly the letterbox bars. Almost
## right, and very easy to stare past. [method _refit] derives both together
## so they cannot drift.
var _fog_world_rect: Rect2 = Rect2()
var _map_scale: float = 0.0
var _map_offset: Vector2 = Vector2.ZERO

## Coalesces a burst of structural signals (procgen adding a few hundred nodes,
## a forced-dealloc cascade) into ONE geometry rebuild at the end of the frame.
var _geometry_dirty: bool = false

# Last camera state the outline was drawn for. Polled rather than signalled
# because the zoom TWEEN moves `zoom` continuously and emits nothing per frame.
var _last_camera_position: Vector2 = Vector2.INF
var _last_camera_zoom: Vector2 = Vector2.ZERO


func _ready() -> void:
	resized.connect(_refit)
	if map_area != null:
		map_area.resized.connect(_refit)
		map_area.gui_input.connect(_on_map_gui_input)
	set_process(false)


func _exit_tree() -> void:
	_binds.release()


## System-lifetime wiring, from [method HudRoot.bind_systems]. [param camera]
## is optional: a level without one (an embedded showcase, a HUD fixture) still
## draws its board and simply has no outline to place.
func bind(graph: Graph, camera: GraphCamera, allocation_system: AllocationSystem) -> void:
	_binds.release()
	_graph = graph
	_camera = camera

	if _graph != null:
		# Topology. `unbind` because none of these handlers wants the argument
		# — and note BindScope stores the Callable it actually connected, which
		# is the only way an `unbind()` is ever releasable (each call mints a
		# fresh one).
		_binds.link(_graph.node_added, _mark_geometry_dirty.unbind(1))
		_binds.link(_graph.node_removed, _mark_geometry_dirty.unbind(1))
		_binds.link(_graph.edge_added, _mark_geometry_dirty.unbind(1))
		_binds.link(_graph.edge_removed, _mark_geometry_dirty.unbind(1))
	if allocation_system != null:
		# Ownership tint. The forced variants matter as much as the gated ones:
		# a dealloc cascade repaints a whole territory neutral.
		_binds.link(allocation_system.allocated, _mark_geometry_dirty.unbind(3))
		_binds.link(allocation_system.deallocated, _mark_geometry_dirty.unbind(2))
		_binds.link(allocation_system.force_deallocated, _mark_geometry_dirty.unbind(2))

	# Only poll when there is something to poll for.
	set_process(_camera != null)
	if _camera == null and viewport_rect_layer != null:
		viewport_rect_layer.clear_view_rect()
	_refit()
	_mark_geometry_dirty()


func _process(_delta: float) -> void:
	if _camera == null or not _camera.is_inside_tree():
		return
	# The outline redraws only when the camera actually moved. Reading `zoom`
	# (live, mid-tween) rather than the camera's step target is what makes the
	# outline glide with the view instead of snapping a frame after the wheel.
	if _camera.global_position == _last_camera_position and _camera.zoom == _last_camera_zoom:
		return
	_last_camera_position = _camera.global_position
	_last_camera_zoom = _camera.zoom
	_push_view_rect()


# ---------------------------------------------------------------- mapping ---

## Recompute the world↔map transform, the fog rect and everything derived from
## them. Aspect-fit with letterboxing, so a wide graph in a square panel keeps
## its proportions rather than shearing.
##
## The bounds are read from the CAMERA's raw AABB + zoom==1.0 margin when one
## is bound, and from the graph's own AABB otherwise — the two agree; the
## camera merely also knows the margin.
func _refit() -> void:
	var area_size: Vector2 = map_area.size if map_area != null else Vector2.ZERO
	_fit(_resolve_world_bounds(), area_size)
	_push_fog_rect()
	_push_view_rect()
	_mark_geometry_dirty()


func _resolve_world_bounds() -> Rect2:
	if _camera != null:
		var raw := _camera.graph_bounds()
		if raw.size != Vector2.ZERO:
			return raw.grow(_camera.pan_margin_base())
	if _graph != null:
		return _graph.get_node_bounds()
	return Rect2()


## The one place the transform is derived. Pure — takes both inputs, touches no
## node — so the mapping and the letterbox/fog agreement are unit-testable
## without a level, a camera or a viewport.
func _fit(world_bounds: Rect2, area_size: Vector2) -> void:
	_world_bounds = world_bounds
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0 \
			or area_size.x <= 0.0 or area_size.y <= 0.0:
		_map_scale = 0.0
		_map_offset = Vector2.ZERO
		_fog_world_rect = Rect2()
		return
	_map_scale = minf(area_size.x / world_bounds.size.x, area_size.y / world_bounds.size.y)
	_map_offset = (area_size - world_bounds.size * _map_scale) * 0.5
	# Expanded to the map area's aspect about the same centre: at this scale
	# the full area covers exactly this much world, which is what the fog
	# quad's UV span means.
	var fog_size := area_size / _map_scale
	_fog_world_rect = Rect2(world_bounds.get_center() - fog_size * 0.5, fog_size)


func _world_to_map(world_pos: Vector2) -> Vector2:
	return (world_pos - _world_bounds.position) * _map_scale + _map_offset


func _map_to_world(map_pos: Vector2) -> Vector2:
	if _map_scale <= 0.0:
		return _world_bounds.get_center()
	return (map_pos - _map_offset) / _map_scale + _world_bounds.position


# --------------------------------------------------------------- geometry ---

func _mark_geometry_dirty() -> void:
	if _geometry_dirty:
		return
	_geometry_dirty = true
	_rebuild_geometry.call_deferred()


## Walk the board once and hand [MinimapGraphLayer] two flat arrays. O(nodes +
## edges), and it runs on structural change — not per frame, and never on a pan.
func _rebuild_geometry() -> void:
	_geometry_dirty = false
	if graph_layer == null:
		return
	var edge_points := PackedVector2Array()
	var edge_colors := PackedColorArray()
	var dot_points := PackedVector2Array()
	var dot_colors := PackedColorArray()
	if _graph != null and _map_scale > 0.0:
		for edge in _graph.get_edges():
			if edge.from == null or edge.to == null or edge.from == edge.to:
				continue
			edge_points.append(_world_to_map(edge.from.global_position))
			edge_points.append(_world_to_map(edge.to.global_position))
			edge_colors.append(_edge_color(edge))
		var half := Vector2(dot_size * 0.5, 0.0)
		for node in _graph.get_skill_nodes():
			# A dot is a segment of length == width rather than a `draw_circle`:
			# it joins the SAME batched call as every other dot, so 2500 nodes
			# stay one draw call. At 2px the difference is not visible.
			var centre := _world_to_map(node.global_position)
			dot_points.append(centre - half)
			dot_points.append(centre + half)
			dot_colors.append(_node_color(node))
	graph_layer.set_geometry(
			edge_points, edge_colors, dot_points, dot_colors, edge_width, dot_size)


## v0's whole colour language: whose is it. The archetype fill + ownership ring
## from #453 replaces this function and nothing else.
func _node_color(node: SkillNode) -> Color:
	var owner_entity: Entity = node.owned_by
	if owner_entity == null:
		return neutral_node_color
	return owner_entity.color


## An edge takes its owner's tint only when BOTH ends are that owner's — a
## contested edge is not territory, and tinting it from one end would draw a
## border further out than the border actually is.
func _edge_color(edge: Edge) -> Color:
	var from_owner: Entity = edge.from.owned_by
	if from_owner != null and from_owner == edge.to.owned_by:
		var tint := from_owner.color
		tint.a *= 0.55
		return tint
	return neutral_edge_color


# ----------------------------------------------------------------- pushes ---

func _push_fog_rect() -> void:
	if fog_layer == null:
		return
	var mat := fog_layer.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(&"minimap_world_rect", Vector4(
			_fog_world_rect.position.x, _fog_world_rect.position.y,
			_fog_world_rect.size.x, _fog_world_rect.size.y))


func _push_view_rect() -> void:
	if viewport_rect_layer == null:
		return
	if _camera == null or not _camera.is_inside_tree() or _map_scale <= 0.0:
		viewport_rect_layer.clear_view_rect()
		return
	var world := _camera.view_rect()
	viewport_rect_layer.set_view_rect(Rect2(
			_world_to_map(world.position), world.size * _map_scale))


# ------------------------------------------------------------------ input ---

## Click or drag to move the camera. A drag is genuinely just a stream of
## jumps (the brief's own framing) — there is no tween, because retargeting a
## glide on every motion event would leave the view a whole tween-duration
## behind the cursor.
##
## Both branches consume the event HARD. `MOUSE_FILTER_STOP` plus
## `accept_event()` should already be enough — allocation runs off
## `SkillNode._on_input_event`, i.e. Area2D physics picking, and Godot only
## queues an event for picking while it is still unhandled — but "should" is
## thin cover for silently allocating a node under the minimap, so the viewport
## is told explicitly as well. v0 releases NO armed click through the panel.
func _on_map_gui_input(event: InputEvent) -> void:
	if _camera == null or _map_scale <= 0.0:
		return
	var wants_pan := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		wants_pan = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		wants_pan = (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if not wants_pan:
		return
	_camera.pan_to(_map_to_world((event as InputEventMouse).position))
	map_area.accept_event()
	get_viewport().set_input_as_handled()
