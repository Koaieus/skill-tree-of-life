@tool
class_name Gate
extends Node2D

## A togglable connection between two [SkillNode]s, owned by the [Graph] under
## its `gates_container`. Same authoring shape as [Edge] (`from` / `to`).
##
## [b]State is never stored.[/b] Open means a real [Edge] exists between the
## endpoints, closed means none does; [method Graph.flip_gates] removes or adds
## that edge, so every mirror follows through the ordinary edge signals.
## See `docs/design/skill_node_addons.md` § Gate.

## A click on the span: left flips this gate, right toggles its seat-local
## lock ([PlayerInputController] routes both).
signal span_clicked(gate: Gate, button: MouseButton)

@export var from: SkillNode
@export var to: SkillNode

@export_group("Look")
## Hue of the span and the midpoint marker; brightness comes only from the tiers.
@export var base_color := Emissive.NEUTRAL:
	set(v):
		base_color = v
		queue_redraw()
## Tier of the faint dashed span a closed gate keeps, so it still reads.
@export var dormant_tier := Emissive.Tier.INERT:
	set(v):
		dormant_tier = v
		queue_redraw()
## Tier of the open gate's midpoint marker.
@export var open_tier := Emissive.Tier.LABEL:
	set(v):
		open_tier = v
		queue_redraw()
@export_range(0.0, 1.0) var dormant_alpha := 0.35:
	set(v):
		dormant_alpha = v
		queue_redraw()
@export_range(0.5, 12.0) var span_width := 3.0:
	set(v):
		span_width = v
		queue_redraw()
@export_range(2.0, 40.0) var marker_radius := 9.0:
	set(v):
		marker_radius = v
		queue_redraw()
## The lock pip: a solid square on the marker's rim, in its own colour.
@export var lock_color := Color(0.95, 0.78, 0.35):
	set(v):
		lock_color = v
		queue_redraw()
@export_range(1.0, 20.0) var lock_pip_size := 6.0:
	set(v):
		lock_pip_size = v
		queue_redraw()
@export_group("Click")
## World px trimmed off each end of the click capsule so a node disc wins where
## they would overlap.
@export_range(0.0, 200.0) var endpoint_inset := 48.0
@export_range(2.0, 60.0) var click_radius := 14.0

@export_group("Rope")
## Played on every flip after load; its knobs live on the rope scene.
@export var rope_scene: PackedScene = preload("res://graph/gate_rope.tscn")

## Display only: the local seat's lock on this gate, pushed by the input side.
## Not world state — never read it for a rule.
var locked_display := false

## Flips play only once armed, one deferred call after [method _ready] — the
## Graph's load-time re-emit, `add_gate(open = true)` and a procgen
## `_setup_level` all add edges in the same frame and must stay silent.
var _armed := false
var _rope: GateRope = null
## The edge an open rope is revealing; null for a snap (that edge is freed).
var _revealing: Edge = null
var _median_span := -1.0

@onready var _span_area: Area2D = get_node_or_null(^"SpanArea")
@onready var _span_shape: CollisionShape2D = get_node_or_null(^"SpanArea/Shape")


func _ready() -> void:
	var graph := get_graph()
	if graph != null and not Engine.is_editor_hint():
		graph.edge_added.connect(_on_edge_changed.bind(true))
		graph.edge_removed.connect(_on_edge_changed.bind(false))
		set_deferred(&"_armed", true)
	if _span_area != null:
		_span_area.input_event.connect(_on_span_input)
	_refresh_geometry()


func set_locked_display(locked: bool) -> void:
	if locked_display == locked:
		return
	locked_display = locked
	queue_redraw()


func _on_edge_changed(edge: Edge, added: bool) -> void:
	if edge != null and ((edge.from == from and edge.to == to) or (edge.from == to and edge.to == from)):
		queue_redraw()
		if _armed:
			_play(edge if added else null)


## Throw a rope onto [param edge] (open) or snap one (null: closed). Which throw
## follows from ownership right now: both ends one entity's → a handshake; one
## owned → from that end; neither → from `from`.
func _play(edge: Edge) -> void:
	_stop_rope()
	if rope_scene == null or from == null or to == null:
		return
	var thrower := from
	var far := to
	var mode := GateRope.Mode.SNAP
	if edge != null:
		mode = GateRope.Mode.THROW
		if from.owned_by != null and from.owned_by == to.owned_by:
			mode = GateRope.Mode.HANDSHAKE
		elif from.owned_by == null and to.owned_by != null:
			thrower = to
			far = from
	var seg := SkillNode.segment_between(thrower, far)
	if seg.size() < 2:
		return
	_rope = rope_scene.instantiate() as GateRope
	add_child(_rope)
	_rope.finished.connect(_on_rope_finished.bind(_rope))
	if edge != null:
		_revealing = edge
		edge.reveal = 0.0
		_rope.reveal_changed.connect(_on_rope_reveal)
	_rope.play(mode, seg[0], seg[1], thrower.base_type_color, far.base_type_color, _reference_span())


func _on_rope_reveal(value: float) -> void:
	if is_instance_valid(_revealing):
		_revealing.reveal = value


func _on_rope_finished(rope: GateRope) -> void:
	if rope != _rope:
		return
	if is_instance_valid(_revealing):
		_revealing.reveal = 1.0
	_revealing = null
	_rope = null


## Cut a playing rope short (a flip landed mid-play): its edge shows in full.
func _stop_rope() -> void:
	if is_instance_valid(_revealing):
		_revealing.reveal = 1.0
	_revealing = null
	if is_instance_valid(_rope):
		_rope.queue_free()
	_rope = null


## The median edge length of this gate's graph, measured once — the span that
## rings at the rope's base frequency.
func _reference_span() -> float:
	if _median_span >= 0.0:
		return _median_span
	_median_span = 0.0
	var graph := get_graph()
	if graph == null:
		return _median_span
	var lengths: Array[float] = []
	for e in graph.get_edges():
		if e.from != null and e.to != null and not e.is_self_loop:
			lengths.append(e.from.global_position.distance_to(e.to.global_position))
	if not lengths.is_empty():
		lengths.sort()
		_median_span = lengths[lengths.size() / 2]
	return _median_span


## Place the click capsule along the span, trimmed by [member endpoint_inset].
func _refresh_geometry() -> void:
	queue_redraw()
	if _span_shape == null or from == null or to == null:
		return
	var a := to_local(from.global_position)
	var b := to_local(to.global_position)
	var capsule := _span_shape.shape as CapsuleShape2D
	if capsule == null:
		return
	capsule.radius = click_radius
	capsule.height = maxf(a.distance_to(b) - 2.0 * endpoint_inset, 2.0 * click_radius)
	_span_area.position = (a + b) * 0.5
	_span_area.rotation = (b - a).angle() + PI * 0.5


func _draw() -> void:
	if from == null or to == null:
		return
	var a := to_local(from.global_position)
	var b := to_local(to.global_position)
	var mid := (a + b) * 0.5
	var open := is_open()
	if not open:
		var dormant := Emissive.at(base_color, Emissive.stops(dormant_tier))
		dormant.a = dormant_alpha
		draw_dashed_line(a, b, dormant, span_width, span_width * 4.0)
		draw_arc(mid, marker_radius, 0.0, TAU, 24, dormant, span_width)
	else:
		draw_circle(mid, marker_radius, Emissive.at(base_color, Emissive.stops(open_tier)))
	if locked_display:
		var s := lock_pip_size
		draw_rect(Rect2(mid + Vector2(-s * 0.5, -marker_radius - s), Vector2(s, s)), lock_color)


func _on_span_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
		span_clicked.emit(self, mb.button_index)


## The Graph this gate belongs to — the nearest [Graph] ancestor, or null.
func get_graph() -> Graph:
	var p := get_parent()
	while p != null and not (p is Graph):
		p = p.get_parent()
	return p as Graph


## Is there a real edge between the endpoints right now?
func is_open() -> bool:
	var graph := get_graph()
	return graph != null and graph.edge_between(from, to) != null


## May [param entity] flip this gate? Iff it owns at least one endpoint and the
## other is neutral or its own. An identity question, not an `ownership_bit`
## relation: an ally owning the far end is another entity, so it freezes the
## gate too — flipping may neither cut someone else's edge nor bridge onto an
## occupied node.
func can_toggle(entity: Entity) -> bool:
	if entity == null or from == null or to == null:
		return false
	var a := from.owned_by
	var b := to.owned_by
	if a != entity and b != entity:
		return false
	return (a == null or a == entity) and (b == null or b == entity)
