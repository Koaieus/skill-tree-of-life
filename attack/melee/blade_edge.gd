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

@export var width: float = 2.0
## VALUE tier over the base hue — a thin stroke needs the full stop to read
## as lit (`docs/domain/hdr-color.md`: coverage is half the effect).
@export var color: Color = Emissive.at(Color(1.0, 0.184, 0.18), Emissive.VALUE)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if from == null or to == null:
		return
	var a := to_local(from.edge_point(to.global_position))
	var b := to_local(to.edge_point(from.global_position))
	if (b - a).length_squared() < 0.01:
		return
	draw_line(a, b, color, width, true)
