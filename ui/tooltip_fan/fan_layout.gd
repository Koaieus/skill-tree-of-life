class_name FanLayout
extends RefCounted

## Pure rect relaxation solver for the tooltip fan: N bodies spring toward
## authored rests while position projection keeps them apart from each
## other, from fixed obstacles, and inside a keep-in rect. No nodes; the
## driver feeds bodies in and reads `position` back each frame. Bloom is not
## a second path — it is this solver started with every body at one point.
##
## Two forces only. (1) A critically damped spring toward `rest` — the
## camera's rubber band (`scenes/camera_2d.gd`): `ω = 1 / settle_seconds`,
## `accel = (rest − pos)·ω² − vel·2ω`, semi-implicit Euler, sub-stepped so
## `ω·dt ≤ MAX_STEP_RATIO`; no transcendentals. (2) Position projection:
## after integrating, `relax_iterations` passes push every overlapping
## inflated pair apart along its minimum-penetration axis — half each for a
## body pair, the whole correction against an obstacle — then `keep_in` is
## applied last and absolutely (a body larger than the window pins to its
## top-left). Projection never touches velocity: the spring keeps pushing and
## the projection keeps holding, which IS the contact equilibrium.
##
## Inflation: `padding` is the gap the solver maintains between any two
## rects. A body-vs-body test inflates each side by `padding / 2`; a
## body-vs-obstacle test inflates the body by the full `padding`.
## Pair order is body index order and every sign has a total fallback
## chain, so the result is deterministic.

## The camera's sub-step cap: `ω·dt` per sub-step never exceeds this.
const MAX_STEP_RATIO := 0.25
const DEFAULT_SETTLE_SECONDS := 0.15
const DEFAULT_PADDING := 8.0
const DEFAULT_RELAX_ITERATIONS := 4
## A critically damped spring's tail is asymptotic: sub-pixel creep for a
## second after the eye has stopped seeing motion. A body within a pixel
## of its rest AND moving under a pixel a step snaps onto the rest and
## stops — the same "within epsilon → snap" contract the driver's pin-angle
## ease already keeps. A body held off its rest by projection never
## qualifies, so contact equilibria are untouched.
const SNAP_EPSILON := 1.0


class Body extends RefCounted:
	var size: Vector2        ## panel rect size (read live by the driver each frame)
	var rest: Vector2        ## authored rest, top-left, fan space
	var position: Vector2    ## solved, top-left
	var velocity: Vector2


## One frame: integrate every spring, relax overlaps, clamp into the window.
## Returns the largest |Δposition| any body took this step.
static func step(bodies: Array[FanLayout.Body], obstacles: Array[Rect2], keep_in: Rect2,
		params: Dictionary, dt: float) -> float:
	var before: PackedVector2Array = PackedVector2Array()
	before.resize(bodies.size())
	for i in bodies.size():
		before[i] = bodies[i].position

	var tau: float = maxf(0.0001, float(params.get("settle_seconds", DEFAULT_SETTLE_SECONDS)))
	_integrate_springs(bodies, tau, dt)

	var padding: float = float(params.get("padding", DEFAULT_PADDING))
	var iterations: int = int(params.get("relax_iterations", DEFAULT_RELAX_ITERATIONS))
	for _pass in iterations:
		_relax_pairs(bodies, padding)
		_relax_obstacles(bodies, obstacles, padding)
	_clamp_into(bodies, keep_in)

	var moved := 0.0
	for i in bodies.size():
		moved = maxf(moved, (bodies[i].position - before[i]).length())
	return moved


## Step at 60 Hz until every body moved less than [param epsilon] in one
## step. Returns the number of steps taken; -1 when [param max_steps] ran out.
static func settle(bodies: Array[FanLayout.Body], obstacles: Array[Rect2], keep_in: Rect2,
		params: Dictionary, max_steps := 600, epsilon := 0.05) -> int:
	const DT := 1.0 / 60.0
	for n in max_steps:
		if step(bodies, obstacles, keep_in, params, DT) < epsilon:
			return n + 1
	return -1


static func _integrate_springs(bodies: Array[FanLayout.Body], tau: float, dt: float) -> void:
	var omega := 1.0 / tau
	var max_step := tau * MAX_STEP_RATIO
	for b in bodies:
		var remaining := dt
		while remaining > 0.0:
			var h := minf(remaining, max_step)
			remaining -= h
			var accel := (b.rest - b.position) * (omega * omega) - b.velocity * (2.0 * omega)
			b.velocity += accel * h
			b.position += b.velocity * h
		if (b.rest - b.position).length() < SNAP_EPSILON \
				and (b.velocity * dt).length() < SNAP_EPSILON:
			b.position = b.rest
			b.velocity = Vector2.ZERO


static func _relax_pairs(bodies: Array[FanLayout.Body], padding: float) -> void:
	var half := padding * 0.5
	for i in bodies.size():
		var a := bodies[i]
		for j in range(i + 1, bodies.size()):
			var b := bodies[j]
			var ra := Rect2(a.position, a.size).grow(half)
			var rb := Rect2(b.position, b.size).grow(half)
			var push := _separation(ra, rb, (b.rest + b.size * 0.5) - (a.rest + a.size * 0.5))
			if push == Vector2.ZERO:
				continue
			a.position -= push * 0.5
			b.position += push * 0.5


static func _relax_obstacles(bodies: Array[FanLayout.Body], obstacles: Array[Rect2],
		padding: float) -> void:
	for b in bodies:
		for o in obstacles:
			var rb := Rect2(b.position, b.size).grow(padding)
			# The obstacle is the fixed side: the body takes the whole push,
			# away from the obstacle, so the arguments are (obstacle, body).
			var push := _separation(o, rb, (b.rest + b.size * 0.5) - o.get_center())
			if push == Vector2.ZERO:
				continue
			b.position += push


## Absolute, last: a body larger than the window pins to its top-left.
static func _clamp_into(bodies: Array[FanLayout.Body], keep_in: Rect2) -> void:
	for b in bodies:
		var max_pos := keep_in.end - b.size
		b.position.x = clampf(b.position.x, keep_in.position.x, maxf(keep_in.position.x, max_pos.x))
		b.position.y = clampf(b.position.y, keep_in.position.y, maxf(keep_in.position.y, max_pos.y))


## The translation that moves [param b] fully clear of [param a] along the
## axis of least penetration, or ZERO when they do not overlap. The sign is
## [param toward] — the offset between where the two WANT to be (rest
## centres), so a pair that blooms from one point separates toward its own
## sectors instead of by whichever rect happens to be wider; a zero component
## falls back to the current centre offset, and failing that +. Sorting by
## rest rather than by current position is what keeps a bloom from jamming
## panels on the wrong side of the node (measured: the seven-panel bloom
## lands every panel in its rest sector, where centre-first left three
## swapped).
static func _separation(a: Rect2, b: Rect2, toward: Vector2) -> Vector2:
	var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var overlap_y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	if overlap_x <= 0.0 or overlap_y <= 0.0:
		return Vector2.ZERO
	var delta := b.get_center() - a.get_center()
	if overlap_x < overlap_y:
		return Vector2(overlap_x * _sign_of(toward.x, delta.x), 0.0)
	return Vector2(0.0, overlap_y * _sign_of(toward.y, delta.y))


static func _sign_of(primary: float, fallback: float) -> float:
	if primary != 0.0:
		return signf(primary)
	if fallback != 0.0:
		return signf(fallback)
	return 1.0
