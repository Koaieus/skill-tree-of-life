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
		_relax_pairs(bodies, padding, keep_in)
		_relax_obstacles(bodies, obstacles, padding, keep_in)
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


static func _relax_pairs(bodies: Array[FanLayout.Body], padding: float, keep_in: Rect2) -> void:
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
			# The split move: the first candidate that leaves BOTH inside the
			# window wins, else the shallowest and the clamp settles it.
			var room_a := _room_for(a, keep_in)
			var room_b := _room_for(b, keep_in)
			var push := candidates[0]
			for c in candidates:
				if room_a.has_point(a.position - c * 0.5) and room_b.has_point(b.position + c * 0.5):
					push = c
					break
			a.position -= push * 0.5
			b.position += push * 0.5


## Obstacles a body overlaps are resolved as ONE merged rect: two obstacles
## closer together than the body (the node's 11 px slot above Roots) would
## otherwise hand it back and forth between them forever.
static func _relax_obstacles(bodies: Array[FanLayout.Body], obstacles: Array[Rect2],
		padding: float, keep_in: Rect2) -> void:
	for b in bodies:
		var rb := Rect2(b.position, b.size).grow(padding)
		var merged := Rect2()
		var any := false
		for o in obstacles:
			if not rb.intersects(o):
				continue
			merged = o if not any else merged.merge(o)
			any = true
		if not any:
			continue
		# The obstacle is the fixed side: the body takes the whole push,
		# away from the obstacle, so the arguments are (obstacle, body).
		var toward := (b.rest + b.size * 0.5) - merged.get_center()
		var candidates := _separations(merged, rb, toward)
		var room := _room_for(b, keep_in)
		var push := candidates[0]
		for c in candidates:
			if room.has_point(b.position + c):
				push = c
				break
		b.position += push


## Absolute, last: a body larger than the window pins to its top-left.
static func _clamp_into(bodies: Array[FanLayout.Body], keep_in: Rect2) -> void:
	for b in bodies:
		var max_pos := keep_in.end - b.size
		b.position.x = clampf(b.position.x, keep_in.position.x, maxf(keep_in.position.x, max_pos.x))
		b.position.y = clampf(b.position.y, keep_in.position.y, maxf(keep_in.position.y, max_pos.y))


## Where a body's top-left may sit and still be inside [param keep_in].
static func _room_for(b: Body, keep_in: Rect2) -> Rect2:
	return Rect2(keep_in.position, keep_in.size - b.size)


## The translations that move [param b] fully clear of [param a], shallowest
## first — each axis, each sign — or empty when they do not overlap. The
## caller takes the first one WITH ROOM: a push the keep-in clamp would undo
## deadlocks the body against the wall, so the next-shallowest direction
## that fits is the one to take (and none fitting, the shallowest, which the
## clamp then settles).
##
## Within an axis the preferred sign is [param toward] — the offset between
## where the two WANT to be (rest centres), so a pair that blooms from one
## point separates toward its own sectors instead of by whichever rect
## happens to be wider; a zero component falls back to the current centre
## offset, and failing that +. Sorting by rest rather than by current
## position is what keeps a bloom from jamming panels on the wrong side of
## the node (measured: the seven-panel bloom lands every panel in its rest
## sector, where centre-first left three swapped).
static func _separations(a: Rect2, b: Rect2, toward: Vector2) -> Array[Vector2]:
	var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var overlap_y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	if overlap_x <= 0.0 or overlap_y <= 0.0:
		return []
	var delta := b.get_center() - a.get_center()
	var sx := _sign_of(toward.x, delta.x)
	var sy := _sign_of(toward.y, delta.y)
	var along_x: Array[Vector2] = [Vector2(overlap_x * sx, 0.0), Vector2(-overlap_x * sx, 0.0)]
	var along_y: Array[Vector2] = [Vector2(0.0, overlap_y * sy), Vector2(0.0, -overlap_y * sy)]
	if overlap_x < overlap_y:
		return along_x + along_y
	return along_y + along_x


static func _sign_of(primary: float, fallback: float) -> float:
	if primary != 0.0:
		return signf(primary)
	if fallback != 0.0:
		return signf(fallback)
	return 1.0
