@tool
class_name Edge
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")

## Visible edge between two SkillNodes. Owns its rendering and listens to
## each endpoint's `owner_changed` / `radius_changed` / `archetype_changed`
## so it can redraw autonomously — "lit" being the common case of both
## endpoints owned by the same entity.
##
## Regular edges render via the `Line2D` child, gradiented between each
## endpoint's own `base_type_color` (archetype tint) so the edge visually
## belongs to the nodes it connects. Self-loops (from == to, no gradient to
## speak of) stay on procedural `_draw` — a Line2D circle-polyline buys
## nothing extra there and arcs are cheap.

signal endpoints_changed

## Lit/unlit/sensed are colour TRANSFORMS applied to each endpoint's own
## archetype tint, not fixed overrides — see `_display_color`.
@export_range(0.0, 1.0, 0.05) var lit_lighten: float = 0.35
@export_range(0.0, 1.0, 0.05) var unlit_desaturate: float = 0.6
@export_range(0.0, 1.0, 0.05) var unlit_darken: float = 0.35
@export_range(0.0, 1.0, 0.05) var lit_alpha: float = 0.95
@export_range(0.0, 1.0, 0.05) var unlit_alpha: float = 0.55
## Sensed = topology hint only (see `sensed` below). Fixed low alpha so a
## sensed edge in pitch-black doesn't outshine a barely-visible unlit edge
## in someone's vision fade-zone, regardless of lit/unlit archetype colour.
@export_range(0.0, 1.0, 0.05) var sensed_alpha: float = 0.35
@export_range(0.0, 1.0, 0.05) var sensed_width_scale: float = 0.75

@export var from: SkillNode:
	set(value):
		if from == value:
			return
		_disconnect_endpoint(from)
		from = value
		_connect_endpoint(from)
		_register_self_loop()
		_update_endpoints()
		_update_visual()
		endpoints_changed.emit()

@export var to: SkillNode:
	set(value):
		if to == value:
			return
		_disconnect_endpoint(to)
		to = value
		_connect_endpoint(to)
		_register_self_loop()
		_update_endpoints()
		_update_visual()
		endpoints_changed.emit()

@export var width: float = 2.0:
	set(v):
		width = v
		_update_visual()

@onready var line_2d: Line2D = $Line2D


## Sensed-but-not-clearly-visible: at least one endpoint is sensed
## (not visible). VisionSystem writes this every recompute. When true,
## the edge renders above the fog overlay so the topology hint reads
## through the darkness — a topology breadcrumb, not a full reveal.
## See docs/design/info_gating.md for the broader info dimensions this
## flag will eventually plug into.
var sensed: bool = false:
	set(value):
		if sensed == value:
			return
		sensed = value
		z_as_relative = not sensed
		z_index = ZLayers.SENSED if sensed else ZLayers.GRAPH_DEFAULT
		_update_visual()

var is_self_loop: bool:
	get(): return from != null and from == to

func _ready() -> void:
	_update_endpoints()
	_update_visual()

func _draw() -> void:
	# Regular edges are drawn by the Line2D child; only self-loops (no
	# straight-line gradient to speak of, from == to) go through _draw.
	if not is_self_loop or from == null:
		return
	_draw_self_loop()

## Lit when both endpoints are owned by the same entity. Override in a
## subclass or replace the predicate later for richer states (e.g. owned
## by anyone vs. owned by the local player).
func is_lit() -> bool:
	return from != null and to != null \
		and from.owned_by != null \
		and from.owned_by == to.owned_by

## Recomputes rendering from current endpoint positions. Call after moving an
## endpoint node directly (bypassing the `from`/`to` setters) — e.g. a
## sandbox/playground layout pass — since Edge only listens for owner/radius/
## archetype changes, not position, and would otherwise keep rendering the
## segment at the endpoints' positions as of connect-time.
func refresh_endpoints() -> void:
	_update_endpoints()
	queue_redraw()

func _update_endpoints() -> void:
	if not is_node_ready() or line_2d == null:
		return
	if from == null or to == null:
		return
	if is_self_loop:
		line_2d.hide()
		queue_redraw()
		return
	var seg := SkillNode.segment_between(from, to)
	if seg.is_empty():
		line_2d.hide()
		return
	line_2d.show()
	line_2d.set_point_position(0, seg[0] - global_position)
	line_2d.set_point_position(1, seg[1] - global_position)

## Recomputes what should be on screen — Line2D gradient stops + width for
## regular edges, or just a redraw for self-loops (colour is resolved fresh
## in `_draw_self_loop`) — from current endpoint archetype tints and the
## lit/sensed state. Cheap enough to fully recompute rather than diff.
func _update_visual() -> void:
	if not is_node_ready() or line_2d == null:
		return
	if from == null or to == null:
		return
	if is_self_loop:
		queue_redraw()
		return
	var lit := is_lit()
	var grad := line_2d.gradient
	if grad == null:
		grad = Gradient.new()
		line_2d.gradient = grad
	grad.set_color(0, _display_color(from.base_type_color, lit))
	grad.set_color(1, _display_color(to.base_type_color, lit))
	line_2d.width = width * (sensed_width_scale if sensed else 1.0)

## Archetype tint → rendered colour. Lit pushes it brighter; unlit
## desaturates toward its own luminance grey and darkens (reads as "off").
## Sensed forces the unlit treatment regardless of actual lit state — owner
## identity sits above the topology gate, so a sensed-but-co-owned edge must
## not leak "lit" through fog — then caps alpha on top at a fixed low floor.
func _display_color(base: Color, lit: bool) -> Color:
	var c := base
	var effective_lit := lit and not sensed
	if effective_lit:
		c = c.lightened(lit_lighten)
		c.a = lit_alpha
	else:
		var gray := c.get_luminance()
		c = c.lerp(Color(gray, gray, gray, c.a), unlit_desaturate)
		c = c.darkened(unlit_darken)
		c.a = unlit_alpha
	if sensed:
		c.a = sensed_alpha
	return c

## Self-loop glyph: a circular ring tangent to the outside of the node,
## sized relative to node radius. The loop center sits at `r + loop_radius`
## from node center along the chosen direction, so the ring's interior
## just kisses the node circumference and never overlaps the node body.
##
## Direction is the bisector of the LARGEST angular gap between the node's
## other edges — keeps the self-loop visually clear of existing edges
## without disturbing them. Falls back to 12 o'clock when the node has no
## other edges. Multiple self-loops on the same node share that direction
## but nest at growing radii (indexed via `from.self_loops`) so they read
## as concentric rings instead of stacking on top of each other.
## Recomputed each draw (cheap; degree ≪ 16 in practice).
func _draw_self_loop() -> void:
	var node_center := from.global_position - global_position
	var r: float = from.radius
	var idx: int = max(from.self_loops.find(self), 0)
	var loop_radius: float = r * 0.55 * (1.0 + idx * 0.4)
	var angle := _self_loop_bisector_angle()
	var loop_center := node_center + Vector2.from_angle(angle) * (r + loop_radius)
	var c := _display_color(from.base_type_color, is_lit())
	var w := width * (sensed_width_scale if sensed else 1.0)
	draw_arc(loop_center, loop_radius, 0.0, TAU, 24, c, w, true)


## Registers `self` into `from.self_loops` the moment both endpoints make
## this edge a self-loop — idempotent, and independent of whoever built the
## edge (Graph.add_edge already does this for runtime/procgen edges, but a
## scene-authored self-loop sets `from`/`to` straight through these setters
## and would otherwise never register). Without this, `_draw_self_loop`'s
## `self_loops.find(self)` returns -1 for every scene-baked self-loop, so
## they'd all nest at the same radius instead of spreading.
func _register_self_loop() -> void:
	if not is_self_loop:
		return
	if not from.self_loops.has(self):
		from.self_loops.append(self)


## Returns the direction (radians) the self-loop should sit in: the
## midpoint of the widest gap between `from`'s other outgoing edges.
## -PI/2 (12 o'clock) when the node has no other edges.
func _self_loop_bisector_angle() -> float:
	if from == null or get_parent() == null:
		return -PI / 2.0
	var node_pos := from.global_position
	var angles: PackedFloat32Array = []
	for sibling in get_parent().get_children():
		if sibling == self or not (sibling is Edge):
			continue
		var other := _other_endpoint(sibling as Edge)
		if other == null:
			continue
		angles.append((other.global_position - node_pos).angle())
	if angles.is_empty():
		return -PI / 2.0
	angles.sort()
	# Widest gap (with wrap-around): place the loop in its bisector.
	var best_gap: float = -1.0
	var best_angle: float = -PI / 2.0
	for i in angles.size():
		var a1: float = angles[i]
		var a2: float = angles[(i + 1) % angles.size()]
		var gap: float = a2 - a1
		if i == angles.size() - 1:
			gap += TAU  # wrap-around closes the circle
		if gap > best_gap:
			best_gap = gap
			best_angle = a1 + gap * 0.5
	return best_angle


## Returns the endpoint of `e` that is NOT `from` — used by self-loop angle
## computation to gather the directions of all other edges incident to
## `from`. Returns null when `e` doesn't touch `from` or is itself a
## self-loop on `from` (those don't contribute a direction).
func _other_endpoint(e: Edge) -> SkillNode:
	if e.from == from and e.to != from:
		return e.to
	if e.to == from and e.from != from:
		return e.from
	return null


func _connect_endpoint(node: SkillNode) -> void:
	if node == null:
		return
	if not node.owner_changed.is_connected(_on_endpoint_owner_changed):
		node.owner_changed.connect(_on_endpoint_owner_changed)
	if not node.radius_changed.is_connected(_on_endpoint_radius_changed):
		node.radius_changed.connect(_on_endpoint_radius_changed)
	if not node.archetype_changed.is_connected(_on_endpoint_archetype_changed):
		node.archetype_changed.connect(_on_endpoint_archetype_changed)


func _disconnect_endpoint(node: SkillNode) -> void:
	if node == null:
		return
	if node.owner_changed.is_connected(_on_endpoint_owner_changed):
		node.owner_changed.disconnect(_on_endpoint_owner_changed)
	if node.radius_changed.is_connected(_on_endpoint_radius_changed):
		node.radius_changed.disconnect(_on_endpoint_radius_changed)
	if node.archetype_changed.is_connected(_on_endpoint_archetype_changed):
		node.archetype_changed.disconnect(_on_endpoint_archetype_changed)


func _on_endpoint_owner_changed() -> void:
	_update_visual()

func _on_endpoint_radius_changed() -> void:
	_update_endpoints()
	queue_redraw()

func _on_endpoint_archetype_changed() -> void:
	_update_visual()
