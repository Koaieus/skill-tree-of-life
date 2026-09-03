@tool
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
##   inbound  (Projectile → Visual)
##     * `_on_launch()`        — once when flight begins (post-delay).
##     * `_on_progress(t)`     — each frame, t ∈ [0, 1].
##     * `_on_arrival()`       — once on impact, before the linger / free.
##     * `_on_crit(tier)`       — called immediately after `_on_launch` when
##       [member crit_tier] > 0, so the visual can scale/tint/shake.
##     * `_on_context(entry)`  — once, at visual instantiation and therefore
##       BEFORE `_on_launch`, with this projectile's [ScheduleEntry] (#543 D6).
##       Everything a per-spell treatment needs to know about WHERE in the cast
##       it sits — beat fraction, normalized magnitude, convergence count,
##       visit index, terminal flag, and its own launch/arrive window. Skipped
##       when no coordinator supplied one.
##   outbound (Visual → Projectile)
##     * `finished` signal     — visual says "I'm fully done draining" so
##       the projectile (and the BattleSystem await chain it feeds) waits
##       on the actual fade-out instead of a fixed linger.
## Any subset is fine; missing inbound methods are skipped, and a missing
## `finished` signal falls back to [member linger_seconds].

signal arrived

@export var path: ProjectilePath
@export var visual_scene: PackedScene
@export var flight_time: float = 0.55
## If true, the projectile's rotation tracks instantaneous travel direction
## so an oriented visual (arrow, missile) faces forward. Symmetric visuals
## (the default dot) ignore it.
@export var face_velocity: bool = true

## Time constant for [member face_velocity], in seconds. `0.0` snaps the
## rotation to the last frame's travel delta, which is what every projectile did
## before this existed and remains the default.
##
## [b]It exists because a jagged path and an oriented visual fight each other.[/b]
## [JitterPath] at a low `smoothing` is deliberately made of hard corners — the
## crackle IS the corners — so within a noise segment the travel delta is steady
## and at each of the ~7 boundaries it lurches sideways for exactly one frame.
## Snapping to that gives a visual a stable heading interrupted by seven
## single-frame spins, which reads as a glitch rather than as an arc, and is why
## [member BoltBody.stretch_along_velocity] was unusable on the lightning family
## (#663). Smoothing spends the corner over several frames instead, so the
## silhouette leans into each kink and recovers.
##
## Framerate-independent and transcendental-free: the per-frame blend is
## `delta / constant`, clamped — no `exp`, per
## `.claude/rules/multiplayer-sync.md`, even though a projectile's facing is
## pure presentation that no peer recomputes.
@export_range(0.0, 0.5, 0.005) var facing_smoothing_seconds: float = 0.0
## Fallback post-arrival wait when the visual scene exposes no `finished`
## signal. With the default [GlowingDot] visual (which DOES emit `finished`)
## this is unused — the projectile waits for the trail to fully drain.
@export var linger_seconds: float = 0.1

## Set by the coordinator when the hit is a critical strike; forwarded to
## the visual via duck-typed `_on_crit(tier)` so it can add emphasis
## (scale, screenshake, color pop). 0 = normal hit; 1+ = crit tier.
var crit_tier: int = 0

## Whether [member facing_smoothing_seconds]'s filter has a heading to ease from
## yet. See the seeding note in `_process`.
var _facing_seeded: bool = false

## This projectile's slot in the compiled [OutcomeSchedule] — the whole render
## context a per-spell visual reads (#543 D6). Set by the coordinator before
## [method launch]; forwarded once, duck-typed as `_on_context(entry)`.
##
## Before #543 a visual received exactly one integer ([member crit_tier]), so
## six of the eight per-spell treatments had no way to know whether they were
## the first hop or the last, the big landing or a graze — data the resolver
## had already computed and thrown away.
var context: ScheduleEntry = null

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
	# Before `_on_launch`, deliberately: a visual that sizes or tints itself
	# from its place in the cast must do so on its FIRST frame, not one hook
	# later with a visible pop.
	if context != null:
		_call_visual(&"_on_context", [context])


func _process(delta: float) -> void:
	if not _launched:
		return
	# Editor-side bottom panels go through long stretches of no process ticks
	# (collapsed panel, just-opened SubViewport, scene editor focus stolen).
	# When ticks resume, the first `delta` can be the whole pause length —
	# enough to advance `_t` past 1.0 in one frame and instant-teleport the
	# projectile to its target before the visual ever spawns. Cap to ~20fps
	# so a single bad frame can advance at most ~9 % of a 0.55 s flight.
	delta = minf(delta, 0.05)
	if _delay > 0.0:
		_delay -= delta
		return
	if not _flying:
		_flying = true
		_call_visual(&"_on_launch", [])
		if crit_tier > 0:
			_call_visual(&"_on_crit", [crit_tier])
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
		# Last trail/particle sample at the impact point — without it the
		# trail visibly ends one frame short of the target.
		_call_visual(&"_on_progress", [1.0])
		_on_arrived()
		return
	var prev := global_position
	var pos := path.evaluate(_t, _origin_pos, _target_pos)
	global_position = pos
	if face_velocity:
		var velocity := pos - prev
		if velocity.length_squared() > 1e-6:
			var heading := velocity.angle()
			# The first sample seeds the filter outright. Easing in from the
			# node's authored rotation would make every smoothed projectile
			# start by swinging round from whatever angle the scene left it at.
			if facing_smoothing_seconds <= 0.0 or not _facing_seeded:
				rotation = heading
				_facing_seeded = true
			else:
				# `lerp_angle`, not `lerp` — it takes the short way round, so a
				# kink across the +/-PI seam eases through it instead of
				# unwinding the long way.
				rotation = lerp_angle(
					rotation, heading, clampf(delta / facing_smoothing_seconds, 0.0, 1.0)
				)
	_call_visual(&"_on_progress", [_t])


# Halt _process before emitting — the post-arrival wait below keeps this node
# alive for `finished` (or `linger_seconds` fallback), during which any further
# _process tick would re-fire `arrived` and any damage-application lambda
# hooked to it. (See the commit that introduced this guard for the regression.)
func _on_arrived() -> void:
	set_process(false)
	_call_visual(&"_on_arrival", [])
	arrived.emit()
	await _wait_for_visual_done()
	queue_free()


# Wait on the visual's own "I'm done dissipating" signal so the projectile
# (and the BattleSystem await chain that feeds off it) stays alive until the
# trail / particles / shader actually finish — not just until the head lands.
func _wait_for_visual_done() -> void:
	if _visual != null and _visual.has_signal(&"finished"):
		await _visual.finished
		return
	if linger_seconds <= 0.0:
		return
	var t := create_tween()
	t.tween_interval(linger_seconds)
	await t.finished


func _call_visual(method: StringName, args: Array) -> void:
	if _visual != null and _visual.has_method(method):
		_visual.callv(method, args)
