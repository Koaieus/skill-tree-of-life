@tool
class_name GlowingDot
extends Node2D

## Default [Projectile] visual: a glowing head with a fading position trail.
## Each trail segment carries its own birth time and fades out on its own
## clock, so the trail keeps dissipating after the head lands — instead of
## the whole thing popping out the instant of impact.
##
## Implements the visual contract:
##   inbound  — `_on_launch()`, `_on_progress(t)`, `_on_arrival()`, `_on_crit(tier)`
##   outbound — [signal finished] (fired once the last trail segment expires)

signal finished

@export var head_radius: float = 6.0
@export var head_glow_radius: float = 16.0
## Seconds each trail segment lives before fading to 0. Also caps how long
## the visual stays alive after impact: [signal finished] fires when the
## oldest segment expires, telling [Projectile] it's safe to free.
@export var segment_lifetime: float = 0.45
@export var head_color: Color = Color(1.0, 0.85, 0.3, 0.95)
@export var head_glow_color: Color = Color(1.0, 0.85, 0.3, 0.18)

var _segments: PackedVector3Array = []
var _emitting: bool = false
var _arrived: bool = false
var _done_emitted: bool = false
var _crit_scale: float = 1.0
var _crit_color: Color = Color.WHITE


func _on_crit(tier: int) -> void:
	var t: float = clampf(tier, 1, 2)
	_crit_scale = lerpf(1.0, 1.8, t / 2.0)
	_crit_color = Color.ORANGE_RED.lerp(Color.RED, (t - 1.0))
	head_radius *= _crit_scale
	head_glow_radius *= _crit_scale
	head_color = _crit_color
	head_glow_color = Color(_crit_color.r, _crit_color.g, _crit_color.b, head_glow_color.a)


func _ready() -> void:
	# Idle until launched — no point ticking a node that's just been
	# instantiated by a coordinator and hasn't started flying yet.
	set_process(false)


func _on_launch() -> void:
	_emitting = true
	set_process(true)
	queue_redraw()


func _on_progress(_t: float) -> void:
	if not _emitting:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	_segments.append(Vector3(global_position.x, global_position.y, now))


func _on_arrival() -> void:
	_emitting = false
	_arrived = true


func _process(_delta: float) -> void:
	if _segments.size() > 0:
		var now: float = Time.get_ticks_msec() / 1000.0
		var write: int = 0
		for i in _segments.size():
			var seg: Vector3 = _segments[i]
			if now - seg.z < segment_lifetime:
				_segments[write] = seg
				write += 1
		if write != _segments.size():
			_segments.resize(write)
	if _emitting or _segments.size() > 0:
		queue_redraw()
	if _arrived and _segments.is_empty() and not _done_emitted:
		_done_emitted = true
		set_process(false)
		finished.emit()


func _draw() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	for i in _segments.size():
		var seg: Vector3 = _segments[i]
		var age: float = now - seg.z
		var life: float = clampf(1.0 - age / segment_lifetime, 0.0, 1.0)
		var pos: Vector2 = to_local(Vector2(seg.x, seg.y))
		var col := Color(head_color.r, head_color.g, head_color.b,
				head_color.a * life * 0.6)
		draw_circle(pos, head_radius * (0.3 + 0.7 * life), col)
	if _emitting:
		draw_circle(Vector2.ZERO, head_glow_radius, head_glow_color)
		draw_circle(Vector2.ZERO, head_radius, head_color)
