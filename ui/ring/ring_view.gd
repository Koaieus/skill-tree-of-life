@tool
class_name RingView
extends SubViewportContainer
## Draws the inner ring: a display instance of the authored ring scene (its
## positions, edges and keystones are authored there, never computed) in its
## own bloom viewport, a camera fitted to its bounds, its own background and a
## core sigil in place of the centre node's disk. [method show_state] colours
## each cell bought / buyable / locked as [method RingTable.can_buy] says.
##
## The display instance is presentation only: no `owned_by`, no
## AllocationSystem. Input lands on THIS container alone — the SubViewport
## keeps `physics_object_picking` off and [method _propagate_input_event]
## forwards nothing, so a display SkillNode's PickArea never fires (it would
## emit `Events.skill_node_hovered` onto the global bus). Hit-testing is
## [method cell_at].

## The hovered cell changed; `&""` = none.
signal cell_hovered(cell: StringName)
## A left click; `&""` = a miss (or the inert core).
signal cell_clicked(cell: StringName)

enum State { LOCKED, BUYABLE, BOUGHT }

## The rules scene to display — the same one [RingSystem] samples.
@export var ring_scene: PackedScene = preload("res://entity/ring/aspect_ring.tscn"):
	set(v):
		ring_scene = v
		_rebuild()
## The centre node: drawn as [member _sigil], never a cell, never clickable.
@export var core_name: StringName = &"Core":
	set(v):
		core_name = v
		_rebuild()
## Padding (screen px) when the camera fits the ring's bounds. Tentative.
@export_range(0.0, 256.0, 1.0) var fit_margin_px: float = 48.0:
	set(v):
		fit_margin_px = v
		_fit_camera()
## A locked cell's alpha (its tint is kept). Tentative.
@export_range(0.0, 1.0, 0.01) var locked_alpha: float = 0.35:
	set(v):
		locked_alpha = v
		_apply_all()
## The glow tier a bought cell's tint is lifted to. Tentative.
@export var bought_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(v):
		bought_tier = v
		_apply_all()
## The view's own backdrop colour, behind the ring (not the board's space).
@export var background: Color = Color(0.035, 0.04, 0.07):
	set(v):
		background = v
		_apply_background()
## Optional backdrop texture, drawn over [member background] when set.
@export var background_texture: Texture2D = null:
	set(v):
		background_texture = v
		_apply_background()
## Mouse allowance (screen px) past a cell's radius for hover/click.
@export_range(0.0, 32.0, 1.0) var pick_pad_px: float = 6.0
## Gap (world px) between a selected cell's rim and its marker ring. Tentative.
@export_range(0.0, 48.0, 1.0) var marker_gap_px: float = 8.0:
	set(v):
		marker_gap_px = v
		_apply_all()

@onready var _viewport: SubViewport = %Viewport
@onready var _display: Node2D = %Display
@onready var _camera: Camera2D = %Camera
@onready var _fill: ColorRect = %BackgroundFill
@onready var _texture: TextureRect = %BackgroundTexture
@onready var _sigil: RingGlyph = %CoreSigil
@onready var _marker: RingGlyph = %SelectionMarker

var _graph: Graph = null
var _cells: Dictionary[StringName, SkillNode] = {}
var _states: Dictionary[StringName, State] = {}
var _tints: Dictionary[StringName, Color] = {}
var _selected: StringName = &""
var _hovered: StringName = &""


func _ready() -> void:
	resized.connect(_fit_camera)
	mouse_exited.connect(_set_hovered.bind(&""))
	_apply_background()
	_rebuild()


## Colour every cell from `table` + `spent`, and mark `selected` (`&""` = none).
func show_state(table: RingTable, spent: Array[StringName], selected: StringName) -> void:
	for c in _cells:
		var cell := table.cell(c) if table != null else null
		_tints[c] = _tint_of(cell)
		if spent.has(c):
			_states[c] = State.BOUGHT
		elif table != null and table.can_buy(spent, c):
			_states[c] = State.BUYABLE
		else:
			_states[c] = State.LOCKED
	_selected = selected if _cells.has(selected) else &""
	_apply_all()


func state_of(cell: StringName) -> State:
	return _states.get(cell, State.LOCKED)


func selected_cell() -> StringName:
	return _selected


## The in-tree display instance (sample a [RingTable] from it, never mutate it).
func display_graph() -> Graph:
	return _graph


## Where `cell` (or the core) sits, in this container's local coordinates.
func cell_local_position(cell: StringName) -> Vector2:
	var n := _node_named(cell)
	if n == null:
		return Vector2.INF
	var vs := Vector2(_viewport.size)
	var vp := (n.global_position - _camera.position) * _camera.zoom + vs * 0.5
	return vp * float(stretch_shrink)


## The cell under `local` (container coordinates), or `&""`.
func cell_at(local: Vector2) -> StringName:
	if _camera == null or _camera.zoom.x <= 0.0:
		return &""
	var vs := Vector2(_viewport.size)
	var world := _camera.position + (local / float(stretch_shrink) - vs * 0.5) / _camera.zoom
	var best := &""
	var best_d := INF
	for c in _cells:
		var n := _cells[c]
		var d := world.distance_to(n.global_position)
		if d <= n.radius + pick_pad_px / _camera.zoom.x and d < best_d:
			best = c
			best_d = d
	return best


func _propagate_input_event(_event: InputEvent) -> bool:
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hovered(cell_at(event.position))
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(cell_at(event.position))
		accept_event()


func _set_hovered(cell: StringName) -> void:
	if cell == _hovered:
		return
	_hovered = cell
	cell_hovered.emit(cell)


func _node_named(cell: StringName) -> SkillNode:
	if _graph == null:
		return null
	return _graph.get_node_or_null(NodePath("Nodes/" + String(cell))) as SkillNode


func _rebuild() -> void:
	if not is_node_ready():
		return
	if _graph != null:
		_display.remove_child(_graph)
		_graph.free()
		_graph = null
	_cells.clear()
	_states.clear()
	_tints.clear()
	_sigil.hide()
	if ring_scene == null:
		return
	_graph = ring_scene.instantiate() as Graph
	if _graph == null:
		push_error("RingView: ring_scene's root is not a Graph")
		return
	_display.add_child(_graph)
	_display.move_child(_graph, 0)
	for n in _graph.get_skill_nodes():
		if n.name == core_name:
			n.visuals.hide()
			_sigil.position = n.global_position
			_sigil.radius = n.radius
			_sigil.show()
			continue
		_cells[n.name] = n
		_states[n.name] = State.LOCKED
		_tints[n.name] = Emissive.NEUTRAL
	_apply_all()
	_fit_camera()


func _tint_of(cell: RingTable.Cell) -> Color:
	if cell == null:
		return Emissive.NEUTRAL
	var aspect := cell.aspect as Aspect
	if aspect != null and aspect.identity != null:
		return aspect.identity.tint
	if cell.sector != null:
		return cell.sector.tint
	return Emissive.NEUTRAL


func _apply_all() -> void:
	if not is_node_ready():
		return
	for c in _cells:
		var tint: Color = _tints.get(c, Emissive.NEUTRAL)
		match state_of(c):
			State.BOUGHT:
				_cells[c].modulate = Emissive.at(tint, Emissive.stops(bought_tier))
			State.BUYABLE:
				_cells[c].modulate = tint
			_:
				_cells[c].modulate = Color(tint, locked_alpha)
	var sel := _cells.get(_selected, null) as SkillNode
	_marker.visible = sel != null
	if sel != null:
		_marker.position = sel.global_position
		_marker.radius = sel.radius + marker_gap_px


func _apply_background() -> void:
	if not is_node_ready():
		return
	_fill.color = background
	_texture.texture = background_texture
	_texture.visible = background_texture != null


func _fit_camera() -> void:
	if not is_node_ready() or _graph == null:
		return
	var nodes := _graph.get_skill_nodes()
	if nodes.is_empty():
		return
	var bounds := Rect2(nodes[0].global_position, Vector2.ZERO)
	for n in nodes:
		bounds = bounds.merge(Rect2(n.global_position - Vector2.ONE * n.radius,
			Vector2.ONE * n.radius * 2.0))
	var vs := Vector2(_viewport.size)
	var room := vs - Vector2.ONE * fit_margin_px * 2.0 / float(stretch_shrink)
	if room.x <= 0.0 or room.y <= 0.0 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var z := minf(room.x / bounds.size.x, room.y / bounds.size.y)
	_camera.position = bounds.get_center()
	_camera.zoom = Vector2(z, z)
