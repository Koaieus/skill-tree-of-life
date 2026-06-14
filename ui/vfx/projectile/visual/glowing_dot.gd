class_name GlowingDot
extends Node2D

## Default [Projectile] visual: a glowing head with a fading position trail —
## the look the previous monolithic `RangedTracer` drew inline.
##
## Self-contained: tracks its own trail in world space, redraws in its parent's
## local frame. Any other visual scene can replace this — see [Projectile]'s
## docstring for the (duck-typed) hook contract.

@export var head_radius: float = 6.0
@export var head_glow_radius: float = 16.0
@export var trail_len: int = 14
@export var head_color: Color = Color(1.0, 0.85, 0.3, 0.95)
@export var head_glow_color: Color = Color(1.0, 0.85, 0.3, 0.18)

var _active: bool = false
var _trail: Array[Vector2] = []


func _on_launch() -> void:
	_active = true
	queue_redraw()


func _on_progress(_t: float) -> void:
	_trail.push_back(global_position)
	if _trail.size() > trail_len:
		_trail.pop_front()
	queue_redraw()


func _on_arrival() -> void:
	_active = false
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	for i in _trail.size():
		var f := float(i) / float(max(1, trail_len - 1))
		var pos := to_local(_trail[i])
		var col := Color(head_color.r, head_color.g, head_color.b, f * 0.6)
		draw_circle(pos, head_radius * (0.3 + 0.7 * f), col)
	draw_circle(Vector2.ZERO, head_glow_radius, head_glow_color)
	draw_circle(Vector2.ZERO, head_radius, head_color)
