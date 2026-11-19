@tool
extends Node2D
## Ice-hold cue: a self-freeing frost ring on a Frozen node whose ice held — it
## absorbed a copy or ended a spell walk there ([signal Events.ice_held]). The
## ring closes in on the node's rim and fades: the hit stopped HERE, distinct
## from a miss (which shows nothing on the node). Add it to its host FIRST,
## then [method play]. Every knob is tentative, easy to change.

@export var tint: Color = Color(0.7, 0.9, 1.0, 1.0)
## Emissive tier of the ring (a named stop, never a raw float).
@export var tier: Emissive.Tier = Emissive.Tier.VALUE
## Seconds from spawn to gone.
@export_range(0.05, 2.0, 0.01) var duration: float = 0.45
## The ring starts at node radius × start_scale and closes to × end_scale.
@export_range(0.5, 4.0, 0.05) var start_scale: float = 1.6
@export_range(0.5, 4.0, 0.05) var end_scale: float = 1.05
@export_range(0.5, 12.0, 0.5) var width: float = 3.0
## Short tick marks round the ring: reads as frost, not a plain selection ring.
@export_range(0, 24, 1) var ticks: int = 8

var _node_radius := 16.0
var _t := 0.0


## Rings the node of [param node_radius] at [param world_pos]; frees itself.
func play(world_pos: Vector2, node_radius: float) -> void:
	global_position = world_pos
	_node_radius = maxf(node_radius, 1.0)
	_t = 0.0
	var tween := create_tween()
	tween.tween_method(_set_t, 0.0, 1.0, duration)
	tween.tween_callback(queue_free)


func _set_t(t: float) -> void:
	_t = t
	queue_redraw()


func _draw() -> void:
	var ease_t := 1.0 - pow(1.0 - _t, 3.0)
	var r := _node_radius * lerpf(start_scale, end_scale, ease_t)
	var c := Emissive.at(tint, Emissive.stops(tier))
	c.a = 1.0 - _t
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, c, width, true)
	for k in ticks:
		var dir := Vector2.from_angle(TAU * k / maxf(ticks, 1))
		draw_line(dir * (r - width * 1.5), dir * (r + width * 1.5), c, width * 0.6, true)
