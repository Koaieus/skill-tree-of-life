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


func _draw() -> void:
	if from == null or to == null:
		return
	var a := from.global_position - global_position
	var b := to.global_position - global_position
	var c := lit_color if is_lit() else color
	draw_line(a, b, c, width, true)


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


func _disconnect_endpoint(node: SkillNode) -> void:
	if node == null:
		return
	if node.owner_changed.is_connected(_on_endpoint_owner_changed):
		node.owner_changed.disconnect(_on_endpoint_owner_changed)


func _on_endpoint_owner_changed() -> void:
	queue_redraw()
