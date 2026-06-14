class_name RangedTracer
extends Node2D

## A single ranged-attack projectile. Spawns at the firing node's position,
## arcs north then bends toward the target via a 3-point Bezier, emits
## [signal arrived] on impact then queue-frees itself.
##
## Code-only — no .tscn. AttackVFX instantiates with `RangedTracer.new()` and
## drives via [method launch]. The body is a custom-drawn glowing circle with
## a fading position trail; lightweight enough that 5–10 tracers in flight is
## a non-event.

signal arrived

const FLIGHT_TIME: float = 0.55
## Scene pixels north of midpoint the Bezier apex sits — gives the upward
## launch + bend feel without lateral mid-flight wandering.
const ARC_HEIGHT: float = 200.0
const HEAD_RADIUS: float = 6.0
const HEAD_GLOW_RADIUS: float = 16.0
const TRAIL_LEN: int = 14
const HEAD_COLOR: Color = Color(1.0, 0.85, 0.3, 0.95)
const HEAD_GLOW_COLOR: Color = Color(1.0, 0.85, 0.3, 0.18)

var _hit: DamageInstance
var _start: Vector2
var _end: Vector2
var _apex: Vector2
var _t: float = 0.0
var _delay: float = 0.0
var _flying: bool = false
var _trail: Array[Vector2] = []


func launch(hit: DamageInstance, stagger_seconds: float) -> void:
	_hit = hit
	_delay = max(0.0, stagger_seconds)
	if hit == null or hit.target == null or hit.origin == null:
		# Can't fly without endpoints — fire arrived immediately so the
		# volley counter still ticks down.
		arrived.emit()
		queue_free()
		return
	_start = hit.origin.global_position
	_end = hit.target.global_position
	var mid := _start.lerp(_end, 0.5)
	_apex = mid + Vector2(0.0, -ARC_HEIGHT)
	global_position = _start


func _process(delta: float) -> void:
	if _hit == null:
		return
	if _delay > 0.0:
		_delay -= delta
		return
	_flying = true
	_t += delta / FLIGHT_TIME
	if _t >= 1.0:
		global_position = _end
		_on_arrived()
		return
	# Quadratic Bezier: start → apex → end.
	var u := 1.0 - _t
	global_position = u * u * _start + 2.0 * u * _t * _apex + _t * _t * _end
	_trail.push_back(global_position)
	if _trail.size() > TRAIL_LEN:
		_trail.pop_front()
	queue_redraw()


func _draw() -> void:
	if not _flying:
		return
	# Trail: oldest → newest, fading alpha + shrinking radius.
	for i in _trail.size():
		var t := float(i) / float(max(1, TRAIL_LEN - 1))
		var pos := to_local(_trail[i])
		var col := Color(HEAD_COLOR.r, HEAD_COLOR.g, HEAD_COLOR.b, t * 0.6)
		draw_circle(pos, HEAD_RADIUS * (0.3 + 0.7 * t), col)
	# Head + soft glow.
	draw_circle(Vector2.ZERO, HEAD_GLOW_RADIUS, HEAD_GLOW_COLOR)
	draw_circle(Vector2.ZERO, HEAD_RADIUS, HEAD_COLOR)


func _on_arrived() -> void:
	# Halt _process before emitting — otherwise the linger tween below keeps
	# the node alive for 0.1s while _t stays ≥ 1.0, re-firing `arrived` (and
	# the damage-application lambda hooked to it) every frame.
	set_process(false)
	arrived.emit()
	# Brief linger so the trail has time to render its last frame before
	# the node disappears; without this, fast volleys can pop visually.
	var t := create_tween()
	t.tween_interval(0.1)
	t.finished.connect(queue_free)
