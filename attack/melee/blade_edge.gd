@tool
class_name BladeEdge
extends Node2D

## Pure visual — draws a line between two BladeNodes, trimmed to each rim.
## No collision; hit detection is handled by BladeHitScan against the
## simulated trajectory, not by Godot overlap.

signal endpoints_changed

@export var from: BladeNode:
	set(value):
		from = value
		endpoints_changed.emit()
		queue_redraw()

@export var to: BladeNode:
	set(value):
		to = value
		endpoints_changed.emit()
		queue_redraw()

## Look profile (#256) — width and tier come from here, same resource the
## endpoints draw from. Falls back to [constant BladeNode.DEFAULT_STYLE].
@export var style: BladeStyle = null:
	set(value):
		style = value
		queue_redraw()

## The wielder's identity colour, blended per [member BladeStyle.entity_tint].
@export var tint: Color = Color.TRANSPARENT:
	set(value):
		tint = value
		queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


## An edge is de-lit the moment either vertex it hangs off is — a severed piece
## should not stay strung to the blade by a glowing wire. Read off the endpoints
## rather than tracked here, so there is no second copy of "who is dead" to go
## stale (the model's copy is [BladePopResolver.Result.dead_at]).
func is_disabled() -> bool:
	return (from != null and from.disabled) or (to != null and to.disabled)


func _draw() -> void:
	if from == null or to == null:
		return
	var a := to_local(from.edge_point(to.global_position))
	var b := to_local(to.edge_point(from.global_position))
	if (b - a).length_squared() < 0.01:
		return
	var s: BladeStyle = style if style != null else BladeNode.DEFAULT_STYLE
	draw_line(a, b, s.edge_color(tint, is_disabled()), s.edge_width, true)
