class_name BladeFreeFlight
extends RefCounted

## A severed blade fragment that keeps going (#186).
##
## When a spike pop kills a vertex, everything downstream of it stops being
## reachable from the driven pivot. Before this existed those vertices simply
## vanished, which made a single-spine blade fail CATASTROPHICALLY on its first
## spiked contact — the whole sweep deleted by one node. Here the remainder
## instead coasts on from its velocity at the moment of separation: an UNPINNED
## body, internal constraints only, no driver, nothing steering it. The swing
## degrades instead of being deleted.
##
## [b]Trigger-agnostic by construction.[/b] The entry point takes a
## [BladePopResolver.Fragment] — "these vertices left the blade at this time" —
## and nothing about WHY they left. A spike pop produces one today; #781's
## bunker shatter will produce one through the identical seam
## ([method BladePopResolver.LiveGate._disintegrate_unreachable] is the single
## place a fragment is born, whatever removed the vertex or edge), and needs no
## code here. That is how #186 acceptance 5 is satisfied ahead of #781: not by
## a second path that happens to match, but by there being one path.
##
## [b]There is no disconnection damage scale.[/b] Owner, 2026-09-08:
## [i]"emergent from speed, no halving, but possible a slight drag on
## disconnected pieces"[/i]. A coasting fragment carries its own velocity and
## #779's speed multiplier already gives it less than a driven blade,
## continuously — and more if it happens to be flung fast, which is the
## fantasy. The one authored term is [constant DRAG].
##
## [b]Determinism.[/b] This runs on the AUTHORITY only, inside
## [method MeleeAttackPlan.resolve_against]. Its hits join the same
## [AttackOutcome], so they are captured into the [AttackRecord] like any other
## landing and a peer REPLAYS them — it never re-runs a solver.
## See `.claude/rules/attack-timeline.md` and `.claude/rules/multiplayer-sync.md`.

## Velocity bleed on an unpinned fragment, per second (#186 acceptance 4).
##
## The ONLY authored term in free flight — named here rather than inlined at
## the [method BladeSim.simulate] call precisely so that tuning it is one edit
## in one place, and so that setting it to 0 is a meaningful, testable state:
## at 0 the damping factor is exactly 1.0 and the fragment coasts
## undecelerated, indistinguishable from an undamped Verlet body.
##
## Owner-tunable. At 0.8/s a fragment born at the start of a 1.2 s swing keeps
## roughly 40% of its separation speed by the end of it — enough that a long
## coast reads as losing steam without the fragment stalling mid-screen.
const DRAG: float = 0.8

## One fragment's whole free flight: the state it flew as, the trajectory it
## flew, and the map back to the blade it came off.
class Flight extends RefCounted:
	## Absolute swing time the fragment separated at. Its trajectory's local
	## t=0 is this instant, so a hit at local `t` happened at `birth_t + t`.
	var birth_t: float = 0.0
	var state: BladeState
	var trajectory: BladeTrajectory
	## Local particle index -> index in the ORIGINATING state (which is itself
	## a fragment, for a fragment of a fragment). Ascending.
	var vertices: PackedInt32Array
	## Per-local-particle separation velocity (px/s) this flight started from.
	var velocities: PackedVector2Array


## Cut [param fragment] out of [param source] and fly it.
##
## [param source_traj] is the trajectory `source` was simulated along and
## [param source_birth_t] the absolute time that trajectory's local t=0 is —
## 0.0 for the driven blade, the parent's `birth_t` for a fragment of a
## fragment. Returns null when there is no swing left to fly (a fragment born
## at or past the end of the sweep) or the fragment is empty.
static func spawn(
		source: BladeState,
		source_traj: BladeTrajectory,
		source_birth_t: float,
		fragment: BladePopResolver.Fragment,
		swing_duration: float,
		drag: float = DRAG) -> Flight:
	if source == null or source_traj == null or fragment == null:
		return null
	if fragment.vertices.is_empty():
		return null
	var duration := swing_duration - fragment.t
	if duration <= 0.0:
		return null
	var dt: float = source_traj.sample_dt
	if dt <= 0.0:
		return null

	var local_t := maxf(0.0, fragment.t - source_birth_t)
	var pose := source_traj.sample(local_t)
	var prev_pose := source_traj.sample(maxf(0.0, local_t - dt))
	if pose.is_empty():
		return null

	var flight := Flight.new()
	flight.birth_t = fragment.t
	flight.vertices = fragment.vertices
	flight.state = _build_state(source, pose, fragment.vertices)
	# Separation velocity, straight off the driven pose the vertex was in one
	# sample earlier — the "velocity at the moment of disconnection" the issue
	# asks for, read from the trajectory rather than re-derived, so it is
	# exactly what the pinned solver had it doing.
	var velocities := PackedVector2Array()
	velocities.resize(fragment.vertices.size())
	for i in fragment.vertices.size():
		var src: int = fragment.vertices[i]
		velocities[i] = (pose[src] - prev_pose[src]) / dt
	flight.velocities = velocities
	# No drivers: an unpinned body has no handle to be swung by. Everything it
	# does from here is its own momentum plus its own internal constraints.
	flight.trajectory = BladeSim.simulate(
			flight.state, [] as Array[BladeDriver], duration, dt,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true,
			drag, velocities)
	return flight


## The fragment as a standalone [BladeState]: compacted index space, every
## particle DYNAMIC, and only the constraints whose both ends came along.
##
## Compacted rather than full-width-with-holes so that every consumer
## downstream — [BladeHitScan]'s per-particle loop, [BladePopResolver.LiveGate]'s
## `dead_at`, the struct-of-arrays layout itself — sees an ordinary blade with
## no gaps to special-case. The map back out lives on [member Flight.vertices].
static func _build_state(
		source: BladeState,
		pose: PackedVector2Array,
		vertices: PackedInt32Array) -> BladeState:
	var local_of: Dictionary = {}
	for i in vertices.size():
		local_of[vertices[i]] = i

	var positions: Array[Vector2] = []
	var radii: Array[float] = []
	var inner: Array[float] = []
	for i in vertices.size():
		var src: int = vertices[i]
		positions.append(pose[src])
		radii.append(source.radii[src] if src < source.radii.size() else 0.0)
		inner.append(source.inner_radii[src] if src < source.inner_radii.size() else 0.0)

	var edges: Array[Vector2i] = []
	for e_idx in source.edges.size():
		if source.is_edge_removed(e_idx):
			continue
		var e := source.edges[e_idx]
		if not (local_of.has(e.x) and local_of.has(e.y)):
			continue
		edges.append(Vector2i(local_of[e.x], local_of[e.y]))

	var state := BladeState.build(positions, 0, edges, radii, inner)
	# UNPINNED: `build` zeroes the pivot's inverse mass, which is exactly the
	# pin this body no longer has. Vertex 0 is a BFS root and nothing else.
	for i in state.inv_masses.size():
		state.inv_masses[i] = 1.0
	state.is_unpinned = true
	for i in vertices.size():
		var src: int = vertices[i]
		if src < source.vertex_damage.size():
			state.vertex_damage[i] = source.vertex_damage[src]
		if src < source.vertex_blunting.size():
			state.vertex_blunting[i] = source.vertex_blunting[src]
	# Nothing per-EDGE is carried across, and there is no source array to carry:
	# under ADR 0005 an edge holds no stats at all, derived or otherwise. The
	# fragment's edges come along for RIGIDITY — the constraint rebuild just
	# below is what they are for — and, once #781 lands, for something to break.

	# Rest lengths and compliance come from the SOURCE's constraints, not from
	# `build`'s "rest = the distance they happen to be at right now". A blade
	# mid-swing is stretched, and re-resting it at the deformed length would
	# freeze that stretch in as the fragment's true shape. Rebuilding the list
	# this way also carries a phantom brace (ClampAddon's weld) across for free
	# whenever both of its ends came along — a braced fragment stays braced.
	state.constraints.clear()
	for c in source.constraints:
		var dc := c as BladeDistanceConstraint
		if dc == null:
			continue
		if not (local_of.has(dc.a) and local_of.has(dc.b)):
			continue
		var copy := BladeDistanceConstraint.new(local_of[dc.a], local_of[dc.b], dc.rest)
		copy.compliance = dc.compliance
		state.constraints.append(copy)
	return state
