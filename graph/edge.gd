@tool
class_name Edge
extends Node2D

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
		z_index = 1001 if sensed else 0
		queue_redraw()


func _draw() -> void:
	if from == null or to == null:
		return
	var a := from.global_position - global_position
	var b := to.global_position - global_position                                                                                                            
	var dir := (b - a).normalized()
	var a_trim := a + dir * from.radius                                                                                                                      
	var b_trim := b - dir * to.radius                           
	if (b_trim - a_trim).dot(dir) <= 0.0:
		return  # nodes overlap — nothing to draw
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
