class_name FanLayout
extends RefCounted

## Pure rect relaxation solver for the tooltip fan: N bodies spring toward
## authored rests while position projection keeps them apart from each
## other, from fixed obstacles, and inside a keep-in rect. No nodes; the
## driver feeds bodies in and reads `position` back each frame. The solver is
## bloom-agnostic: [FanAnchorDriver] solves warm and flies a blooming panel
## onto its solved spot as a separate visual leg (a lone body, no obstacles).
##
## Two forces only. (1) A critically damped spring toward `rest` clamped
## into the window — the camera's rubber band (`scenes/camera_2d.gd`):
## `ω = 1 / settle_seconds`, `accel = (rest − pos)·ω² − vel·2ω`,
## semi-implicit Euler, sub-stepped so `ω·dt ≤ MAX_STEP_RATIO`; no
## transcendentals. (2) Position projection: after integrating, up to
## `relax_iterations` passes push every overlapping inflated pair apart —
## half each for a body pair (a wall's share going to the partner), the
## whole correction against an obstacle — then `keep_in` is applied last
## and absolutely (a body larger than the window pins to its top-left).
## Contact is INELASTIC: on each axis projection corrected, the velocity
## driving into the correction is dropped. A body held off its rest then
## re-presses its contact by one frame's spring pull, not by the closing
## speed it built up — which is what lets a crowded fan against a wall
## come to rest instead of reshuffling every frame.
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
## A cap, not a count: passes stop at the first one that moves nothing. A
## chain of panels pressed against a wall needs one pass per link to resolve
## — too few leaves a residual the spring re-opens, and the chain jitters.
const DEFAULT_RELAX_ITERATIONS := 16
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
	_integrate_springs(bodies, tau, dt, keep_in)
	var integrated: PackedVector2Array = PackedVector2Array()
	integrated.resize(bodies.size())
	for i in bodies.size():
		integrated[i] = bodies[i].position

	var padding: float = float(params.get("padding", DEFAULT_PADDING))
	var iterations: int = int(params.get("relax_iterations", DEFAULT_RELAX_ITERATIONS))
	for _pass in iterations:
		var pushed := _relax_pairs(bodies, padding, keep_in)
		pushed = _relax_obstacles(bodies, obstacles, padding, keep_in) or pushed
		if not pushed:
			break
	_clamp_into(bodies, keep_in)
	for i in bodies.size():
		_absorb_contact(bodies[i], bodies[i].position - integrated[i])

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


## Springs pull toward the rest clamped into the window: a rest the window
## cuts off is unreachable, and pulling at it anyway only presses the body
## into the wall and every neighbour between.
static func _integrate_springs(bodies: Array[FanLayout.Body], tau: float, dt: float,
		keep_in: Rect2) -> void:
	var omega := 1.0 / tau
	var max_step := tau * MAX_STEP_RATIO
	for b in bodies:
		var room := _room_for(b, keep_in)
		var target := b.rest.clamp(room.position, room.end.max(room.position))
		var remaining := dt
		while remaining > 0.0:
			var h := minf(remaining, max_step)
			remaining -= h
			var accel := (target - b.position) * (omega * omega) - b.velocity * (2.0 * omega)
			b.velocity += accel * h
			b.position += b.velocity * h
		if (target - b.position).length() < SNAP_EPSILON \
				and (b.velocity * dt).length() < SNAP_EPSILON:
			b.position = target
			b.velocity = Vector2.ZERO


## Inelastic contact: on each axis the projection corrected, the velocity
## component driving INTO that correction is dropped. Without it a body held
## off its rest keeps the spring's full closing speed (hundreds of px/s),
## re-penetrates its neighbours by that much every frame, and the
## order-dependent pushes reshuffle the cluster forever. Velocity along the
## correction, or on an untouched axis, is kept.
static func _absorb_contact(b: Body, correction: Vector2) -> void:
	if correction.x != 0.0 and signf(b.velocity.x) != signf(correction.x):
		b.velocity.x = 0.0
	if correction.y != 0.0 and signf(b.velocity.y) != signf(correction.y):
		b.velocity.y = 0.0


## True when any pair was pushed apart.
static func _relax_pairs(bodies: Array[FanLayout.Body], padding: float, keep_in: Rect2) -> bool:
	var pushed := false
	var half := padding * 0.5
	for i in bodies.size():
		var a := bodies[i]
		for j in range(i + 1, bodies.size()):
			var b := bodies[j]
			var ra := Rect2(a.position, a.size).grow(half)
			var rb := Rect2(b.position, b.size).grow(half)
			var toward := (b.rest + b.size * 0.5) - (a.rest + a.size * 0.5)
			var candidates := _separations(ra, rb, toward)
			if candidates.is_empty():
				continue
			# Each candidate splits half each, and the window is infinite
			# mass: what a wall takes out of one side's half goes to the
			# other, so a body flush on a wall still separates by the
			# shallow push, its partner taking it. The first candidate that
			# leaves BOTH inside wins; none fitting, the shallowest, which
			# the clamp settles.
			var room_a := _room_for(a, keep_in)
			var room_b := _room_for(b, keep_in)
			var move_a := -candidates[0] * 0.5
			var move_b := candidates[0] * 0.5
			for c in candidates:
				var ma := _walled(a.position, -c * 0.5, room_a)
				var mb := _walled(b.position, c + ma, room_b)
				ma = _walled(a.position, mb - c, room_a)
				if (mb - ma).is_equal_approx(c):
					move_a = ma
					move_b = mb
					break
			a.position += move_a
			b.position += move_b
			pushed = true
	return pushed


## Obstacles a body overlaps are resolved as ONE merged rect, grown until
## the chosen escape lands clear of every obstacle: two obstacles closer
## together than the body (the node's 11 px slot above Roots) would
## otherwise hand it back and forth between them forever — out of Roots
## upward into the node, out of the node downward past Roots.
static func _relax_obstacles(bodies: Array[FanLayout.Body], obstacles: Array[Rect2],
		padding: float, keep_in: Rect2) -> bool:
	var pushed := false
	for b in bodies:
		var rb := Rect2(b.position, b.size).grow(padding)
		var merged := Rect2()
		var used := {}
		for i in obstacles.size():
			if rb.intersects(obstacles[i]):
				merged = obstacles[i] if used.is_empty() else merged.merge(obstacles[i])
				used[i] = true
		if used.is_empty():
			continue
		var room := _room_for(b, keep_in)
		var push := Vector2.ZERO
		while true:
			push = _obstacle_push(b, rb, merged, room)
			var landed := rb
			landed.position += push
			var grew := false
			for i in obstacles.size():
				if not used.has(i) and landed.intersects(obstacles[i]):
					merged = merged.merge(obstacles[i])
					used[i] = true
					grew = true
			if not grew:
				break
		b.position += push
		pushed = true
	return pushed


## The obstacle is the fixed side: the body takes the whole push, away from
## the obstacle, so the arguments are (obstacle, body).
static func _obstacle_push(b: Body, rb: Rect2, merged: Rect2, room: Rect2) -> Vector2:
	var toward := (b.rest + b.size * 0.5) - merged.get_center()
	var candidates := _separations(merged, rb, toward)
	for c in candidates:
		if _fits(b.position + c, room):
			return c
	return candidates[0]


## Absolute, last: a body larger than the window pins to its top-left.
static func _clamp_into(bodies: Array[FanLayout.Body], keep_in: Rect2) -> void:
	for b in bodies:
		var max_pos := keep_in.end - b.size
		b.position.x = clampf(b.position.x, keep_in.position.x, maxf(keep_in.position.x, max_pos.x))
		b.position.y = clampf(b.position.y, keep_in.position.y, maxf(keep_in.position.y, max_pos.y))


## [param move] from [param from], cut short by the walls of [param room].
static func _walled(from: Vector2, move: Vector2, room: Rect2) -> Vector2:
	return (from + move).clamp(room.position, room.end.max(room.position)) - from


## Where a body's top-left may sit and still be inside [param keep_in].
static func _room_for(b: Body, keep_in: Rect2) -> Rect2:
	return Rect2(keep_in.position, keep_in.size - b.size)


## Edge-INCLUSIVE containment. `Rect2.has_point` excludes the right/bottom
## edge, and the clamp parks a body exactly on `keep_in.end - size` — an
## exclusive test would reject every push that keeps that coordinate and
## fall back to the deadlock direction on the right and bottom walls.
static func _fits(p: Vector2, room: Rect2) -> bool:
	return p == p.clamp(room.position, room.end)


## The translations that move [param b] fully clear of [param a] — the
## shallower-overlap axis first, on each axis the preferred sign first — or
## empty when they do not overlap. The
## caller takes the first one WITH ROOM: a push the keep-in clamp would undo
## deadlocks the body against the wall, so the next-shallowest direction
## that fits is the one to take (and none fitting, the shallowest, which the
## clamp then settles).
##
## Within an axis the preferred sign depends on how DEEP the overlap is.
## A deep one (past half the smaller extent — a bloom from one point, a
## pair whose centres have crossed) sorts by [param toward], the offset
## between where the two WANT to be (rest centres), so it separates toward
## its own sectors instead of by whichever rect happens to be wider: the
## seven-panel bloom lands every panel in its rest sector, where
## centre-first left three swapped. A shallow one is a CONTACT and sorts by
## the current centre offset — the minimum-penetration push. Sorting a
## contact by rest instead throws the pair the whole way through each other
## (hundreds of px for a few px of overlap); when something blocks the far
## side the next pass throws it back, and the fan limit-cycles. A zero
## component falls back to the other offset, and failing that +.
static func _separations(a: Rect2, b: Rect2, toward: Vector2) -> Array[Vector2]:
	var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var overlap_y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	if overlap_x <= 0.0 or overlap_y <= 0.0:
		return []
	var delta := b.get_center() - a.get_center()
	var deep_x := overlap_x > 0.5 * minf(a.size.x, b.size.x)
	var deep_y := overlap_y > 0.5 * minf(a.size.y, b.size.y)
	var sx := _sign_of(toward.x, delta.x) if deep_x else _sign_of(delta.x, toward.x)
	var sy := _sign_of(toward.y, delta.y) if deep_y else _sign_of(delta.y, toward.y)
	# The distance that clears [param b] on each side is NOT the overlap: it
	# is the whole way past [param a]'s far edge when pushing through it.
	# A contact never passes through its neighbour: only a deep axis offers
	# the far-edge clear as a fallback.
	var along_x: Array[Vector2] = [_clear_x(a, b, sx)]
	if deep_x:
		along_x.append(_clear_x(a, b, -sx))
	var along_y: Array[Vector2] = [_clear_y(a, b, sy)]
	if deep_y:
		along_y.append(_clear_y(a, b, -sy))
	if overlap_x < overlap_y:
		return along_x + along_y
	return along_y + along_x


static func _clear_x(a: Rect2, b: Rect2, sign: float) -> Vector2:
	return Vector2(a.end.x - b.position.x if sign > 0.0 else a.position.x - b.end.x, 0.0)


static func _clear_y(a: Rect2, b: Rect2, sign: float) -> Vector2:
	return Vector2(0.0, a.end.y - b.position.y if sign > 0.0 else a.position.y - b.end.y)


static func _sign_of(primary: float, fallback: float) -> float:
	if primary != 0.0:
		return signf(primary)
	if fallback != 0.0:
		return signf(fallback)
	return 1.0
