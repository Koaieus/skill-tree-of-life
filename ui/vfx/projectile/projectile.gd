class_name Projectile
extends Node2D

## A single projectile-shaped VFX element. Pure kinematics + visual delegation;
## carries no game-state references. Spawned and configured by a
## [VFXCoordinator]; the coordinator wires [signal arrived] to whatever
## game-state mutation (damage, hit-flash trigger, etc.) the action requires.
##
## Composition, two axes:
##   * [member path]: how it moves — a [ProjectilePath] resource (Bezier arc,
##     authored Curve2D, future homing / parabola / etc.).
##   * [member visual_scene]: what it looks like — any [PackedScene]; instantiated
##     as a child so its transform rides along.
##
## Visual scene hook contract (duck-typed; future commits may formalise as a
## typed `ProjectileVisual` base class):
##   * `_on_launch()`        — once when flight begins (post-delay).
##   * `_on_progress(t)`     — each frame, t ∈ [0, 1].
##   * `_on_arrival()`       — once on impact, before the linger / free.
## Any subset is fine; missing methods are skipped.

signal arrived

@export var path: ProjectilePath
@export var visual_scene: PackedScene
@export var flight_time: float = 0.55
## If true, the projectile's rotation tracks instantaneous travel direction
## so an oriented visual (arrow, missile) faces forward. Symmetric visuals
## (the default dot) ignore it.
@export var face_velocity: bool = true
## Brief tween after [signal arrived] so trail/particles have a frame to finish
## rendering before [method queue_free] tears the node down.
@export var linger_seconds: float = 0.1

var _origin_pos: Vector2
var _target_pos: Vector2
var _delay: float = 0.0
var _t: float = 0.0
var _launched: bool = false
var _flying: bool = false
var _visual: Node


## Snap origin/target at launch (no homing). [param delay] gates the first
## frame of motion — used by volley coordinators to stagger shots without
## scheduling separate tween timers.
func launch(origin: Vector2, target: Vector2, delay: float = 0.0) -> void:
	_origin_pos = origin
	_target_pos = target
	_delay = max(0.0, delay)
	global_position = origin
	_launched = true
	_instantiate_visual()


func _instantiate_visual() -> void:
	if visual_scene == null or _visual != null:
		return
	_visual = visual_scene.instantiate()
	add_child(_visual)


func _process(delta: float) -> void:
	if not _launched:
		return
	if _delay > 0.0:
		_delay -= delta
		return
	if not _flying:
		_flying = true
		_call_visual(&"_on_launch", [])
	if path == null:
		# Mis-configured projectile — fall through to target immediately so
		# the volley counter still ticks. Warn once.
		push_warning("Projectile has no `path` — falling through to target")
		global_position = _target_pos
		_on_arrived()
		return
	_t += delta / max(0.001, flight_time)
	if _t >= 1.0:
		_t = 1.0
		global_position = _target_pos
		_on_arrived()
		return
	var prev := global_position
	var pos := path.evaluate(_t, _origin_pos, _target_pos)
	global_position = pos
	if face_velocity:
		var velocity := pos - prev
		if velocity.length_squared() > 1e-6:
			rotation = velocity.angle()
	_call_visual(&"_on_progress", [_t])


# Halt _process before emitting — the linger tween below keeps this node alive
# for `linger_seconds`, during which any further _process tick would re-fire
# arrived and any damage-application lambda hooked to it. (See the commit that
# introduced this guard for the regression.)
func _on_arrived() -> void:
	set_process(false)
	_call_visual(&"_on_arrival", [])
	arrived.emit()
	if linger_seconds <= 0.0:
		queue_free()
		return
	var t := create_tween()
	t.tween_interval(linger_seconds)
	t.finished.connect(queue_free)


func _call_visual(method: StringName, args: Array) -> void:
	if _visual != null and _visual.has_method(method):
		_visual.callv(method, args)
