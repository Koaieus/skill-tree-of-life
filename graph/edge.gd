@tool
class_name Edge
extends Node2D

const ZLayers = preload("res://ui/z_layers.gd")

## Visible edge between two SkillNodes. Owns its rendering and listens to
## each endpoint's `owner_changed` so it can redraw lit/unlit autonomously —
## "lit" being the common case of both endpoints owned by the same entity.

signal endpoints_changed

@export var from: SkillNode:
	set(value):
		if from == value:
			return
		_disconnect_endpoint(from)
		from = value
		_connect_endpoint(from)
		endpoints_changed.emit()
		queue_redraw()

@export var to: SkillNode:
	set(value):
		if to == value:
			return
		_disconnect_endpoint(to)
		to = value
		_connect_endpoint(to)
		endpoints_changed.emit()
		queue_redraw()

@export var width: float = 2.0
@export var color: Color = Color(0.55, 0.55, 0.6, 0.55)
@export var lit_color: Color = Color(1.0, 0.85, 0.4, 0.95)

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
		queue_redraw()


func _draw() -> void:
	if from == null or to == null:
		return
	# Self-loop branch: from and to are the same node. Render as a small
	# loop arc tangent to the top of the node so the player can read it as
	# "+2 degree, this is a Resonator setup."
	if from == to:
		_draw_self_loop()
		return
	var seg := SkillNode.segment_between(from, to)
	if seg.is_empty():
		return  # nodes overlap — nothing to draw
	var a_trim := seg[0] - global_position
	var b_trim := seg[1] - global_position
	if sensed:
		# Sensed = topology hint only. Use the unlit colour (never lit,
		# even if both endpoints happen to share owner: owner identity is
		# above the topology gate) at a thinner stroke so it reads as
		# "structure breadcrumb" not "I see this edge clearly."
		# Low floor: sensed edges z-promote above the fog, so this alpha
		# applies regardless of local darkness. Keep it modest so a sensed
		# edge in pitch-black doesn't outshine a barely-visible unlit edge
		# in someone's vision fade-zone.
		var sc := Color(color.r, color.g, color.b, 0.35)
		draw_line(a_trim, b_trim, sc, width * 0.75, true)
		return
	var c := lit_color if is_lit() else color
	draw_line(a_trim, b_trim, c, width, true)

## Lit when both endpoints are owned by the same entity. Override in a
## subclass or replace the predicate later for richer states (e.g. owned
## by anyone vs. owned by the local player).
func is_lit() -> bool:
	return from != null and to != null \
		and from.owned_by != null \
		and from.owned_by == to.owned_by


## Self-loop glyph: a circular ring tangent to the outside of the node,
## sized relative to node radius. The loop center sits at `r + loop_radius`
## from node center along the chosen direction, so the ring's interior
## just kisses the node circumference and never overlaps the node body.
##
## Direction is the bisector of the LARGEST angular gap between the node's
## other edges — keeps the self-loop visually clear of existing edges
## without disturbing them. Falls back to 12 o'clock when the node has no
## other edges. Recomputed each draw (cheap; degree ≪ 16 in practice).
func _draw_self_loop() -> void:
	var node_center := from.global_position - global_position
	var r: float = from.radius
	var loop_radius: float = r * 0.55
	var angle := _self_loop_bisector_angle()
	var loop_center := node_center + Vector2.from_angle(angle) * (r + loop_radius)
	if sensed:
		var sc := Color(color.r, color.g, color.b, 0.35)
		draw_arc(loop_center, loop_radius, 0.0, TAU, 24, sc, width * 0.75, true)
		return
	var c := lit_color if is_lit() else color
	draw_arc(loop_center, loop_radius, 0.0, TAU, 24, c, width, true)


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


func _disconnect_endpoint(node: SkillNode) -> void:
	if node == null:
		return
	if node.owner_changed.is_connected(_on_endpoint_owner_changed):
		node.owner_changed.disconnect(_on_endpoint_owner_changed)
	if node.radius_changed.is_connected(_on_endpoint_radius_changed):
		node.radius_changed.disconnect(_on_endpoint_radius_changed)


func _on_endpoint_owner_changed() -> void:
	queue_redraw()
	
func _on_endpoint_radius_changed() -> void:
	queue_redraw()
