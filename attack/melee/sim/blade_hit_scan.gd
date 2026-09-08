class_name BladeHitScan
extends RefCounted

## Hit detection over a BladeTrajectory via the 2D physics server.
##
## Each sub-step, every blade particle is queried as a circle at its
## sampled position, and every blade edge as a swept CAPSULE along its
## sampled endpoints, trimmed back to the rim of each endpoint's own disk
## (#785) so a hub never deals vertex + one-per-incident-edge. A cheap
## whole-blade bounding-box query short-circuits any substep sweeping empty
## space; see [method _is_region_empty]. The physics server returns whatever
## colliders overlap — this module doesn't encode target geometry at all; targets
## just publish a CollisionShape2D and we get hits back.
##
## Determinism: queries are a pure function of (sim positions, world
## state) [b]only while no query hits [constant _MAX_HITS_PER_QUERY][/b] —
## see that constant. As long as the world state is itself sim-driven and
## the cap is never reached, replays reproduce the same events. Ghost
## previews work the same way because the blade never enters the physics
## world — only the query shapes do.
##
## Result ORDER within one query is broadphase-dependent, for which Godot
## documents no guarantee (#530). Since [MeleeAttackPlan] pops defensive
## spikes DURING its scan of these events, that raw order could make the hit
## SET itself, not merely its arithmetic, depend on broadphase — so [method
## scan] stable-sorts its own output before returning: `t` first (the
## gameplay-meaningful ordering — earlier contact, earlier consequence),
## ties broken on [member SkillNode.stable_id], a value every peer agrees
## on, never on collider identity or query position. This closes the
## WITHIN-one-scan nondeterminism; it does not touch the
## [constant _MAX_HITS_PER_QUERY] gap above, which is a different failure
## mode (a truncated query can drop a collider entirely, not just reorder
## it) and stays open — see `test_gap_melee_hit_detection_truncates_a_physics_query`.
##
## Per-element-per-collider dedup: each particle/edge emits at most one
## event per collider across the whole sweep, on first contact. On top of
## that, per SUBSTEP a collider takes at most one contact overall — the
## highest-damage element wins and the rest are recorded as contacted but
## emit nothing. See [method _resolve_step_contacts].

## Bound on one shape query (one blade element, one substep) — NOT on the
## sweep. A blade particle realistically overlaps 0 nodes in ~99% of substeps
## and 2-3 at the very top of its range, so 16 is deep headroom.
##
## It is a stop-gap against erroneous placement (hundreds of nodes stacked
## into one sweep), not a tuning knob — and reaching it is a [b]determinism
## bug[/b], not merely a dropped hit. Because this scan dedups
## per-element-per-collider on FIRST contact across substeps, a truncated
## query does not necessarily lose a collider: it may be picked up a substep
## later, with a different `t`. So truncation corrupts [member
## BladeHitEvent.t] — the landing ORDER — and which colliders survive the cap
## is broadphase-ordered, for which Godot documents no guarantee. That
## falsifies this file's own purity claim above.
##
## Hence [method _warn_if_truncated]: if this ever fires, the sweep is not
## reproducible and no amount of RNG seeding fixes it. See
## `docs/domain/attack-timeline.md` and
## `test/unit/attack/test_attack_determinism.gd`.
const _MAX_HITS_PER_QUERY := 16

## Loud on truncation, free otherwise (one int compare per query).
static func _warn_if_truncated(hits: Array, element: String, idx: int, t: float) -> void:
	if hits.size() < _MAX_HITS_PER_QUERY:
		return
	push_warning(
		("BladeHitScan: %s %d hit the %d-result query cap at t=%.3f. " +
		"The sweep's hit ORDER is now broadphase-dependent and this attack " +
		"is no longer reproducible — see attack-timeline.md.")
		% [element, idx, _MAX_HITS_PER_QUERY, t])

## Extra margin (px) added to the broad-phase box beyond the blade's own
## extent, so a defender whose collision shape reaches slightly outside its
## SkillNode radius is still admitted as a candidate. Cheap insurance: the
## broad phase must never be tighter than the narrow phase, or it silently
## drops hits.
const _BROAD_PHASE_MARGIN := 64.0

## Half-thickness of an edge capsule (px). Preserves the 1px-wide rectangle
## the pre-#785 edge query used — the collision an edge needs comes mostly
## from the TARGET's own disk, so the edge only has to be a line with a hair
## of width, not a slab.
const _EDGE_RADIUS := 0.5


static func scan(
		trajectory: BladeTrajectory,
		state: BladeState,
		space_state: PhysicsDirectSpaceState2D,
		graph: Graph,
		collision_mask: int = 0xFFFFFFFF,
		exclude: Array[RID] = [],
		broad_phase: bool = true) -> Array[BladeHitEvent]:
	var events: Array[BladeHitEvent] = []
	if space_state == null or trajectory.samples.size() < 2:
		return events
	# element key -> { collider: true }. An element that CONTACTED a collider is
	# recorded here whether or not it won that substep's highest-damage contest
	# (see below) — losing is still contact, so a loser never comes back for a
	# second bite at the same target on a later substep.
	var hit_particle: Dictionary = {}
	var hit_edge: Dictionary = {}
	var samples := trajectory.samples
	var dt := trajectory.sample_dt
	var particle_count := state.positions.size()
	var edges := state.edges
	var radii := state.radii

	var particle_shapes: Array[CircleShape2D] = []
	for p in particle_count:
		var c := CircleShape2D.new()
		c.radius = radii[p]
		particle_shapes.append(c)
	var max_radius := 0.0
	for p in particle_count:
		max_radius = maxf(max_radius, radii[p])
	# Reused across edge queries; height/transform get rewritten each step.
	# A CapsuleShape2D's axis is +Y, hence the +PI/2 on every edge transform.
	var edge_shape := CapsuleShape2D.new()
	edge_shape.radius = _EDGE_RADIUS
	var broad_shape := RectangleShape2D.new()

	var params := PhysicsShapeQueryParameters2D.new()
	params.collision_mask = collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = exclude

	for i in range(1, samples.size()):
		var t: float = float(i) * dt
		var curr := samples[i]
		# Broad phase (#785): ONE query per substep over the blade's whole
		# bounding box. A blade sweeping empty space — the overwhelmingly
		# common substep at 100 vertices / 200 edges — then costs 1 query
		# instead of ~300. The box is a strict superset of every narrow-phase
		# shape (particle disks are inside `max_radius` of a position, edge
		# capsules are inside the convex hull of two positions plus
		# `_EDGE_RADIUS`), so turning this off can only ADD cost, never
		# change the event set — which is what `broad_phase` exists to let a
		# benchmark verify.
		if broad_phase and _is_region_empty(
				space_state, params, broad_shape, curr, max_radius):
			continue
		# (element_kind, element_idx, collider, damage, speed) tuples for THIS
		# substep, in deterministic loop order: particles ascending, then edges
		# ascending.
		var step_contacts: Array = []
		for p_idx in particle_count:
			params.shape = particle_shapes[p_idx]
			params.transform = Transform2D(0.0, curr[p_idx])
			var p_hits := space_state.intersect_shape(params, _MAX_HITS_PER_QUERY)
			_warn_if_truncated(p_hits, "particle", p_idx, t)
			for h in p_hits:
				var collider: Object = h.collider
				var seen = hit_particle.get(p_idx)
				if seen != null and seen.has(collider):
					continue
				step_contacts.append([
					false, p_idx, collider,
					state.vertex_damage[p_idx] if p_idx < state.vertex_damage.size() else 0.0,
					_speed_at(state, i, p_idx)])
		for e_idx in edges.size():
			if state.removed_edges.has(e_idx):
				continue  # severed (#781) — a gone edge collides with nothing
			var e := edges[e_idx]
			var a := curr[e.x]
			var b := curr[e.y]
			var delta := b - a
			var length := delta.length()
			# The capsule covers the segment MINUS the two endpoint hitbox
			# disks (#785 decision): it starts at one vertex's rim and stops at
			# the other's, so a target sitting ON a vertex is inside that
			# vertex's own circle and takes vertex damage only, never vertex +
			# one-per-incident-edge. Short edges whose endpoints' disks already
			# overlap have no exposed span at all and contribute nothing.
			var trimmed := length - radii[e.x] - radii[e.y]
			if trimmed < 1e-4:
				continue
			var dir := delta / length
			var mid := a + dir * (radii[e.x] + trimmed * 0.5)
			edge_shape.height = trimmed + 2.0 * _EDGE_RADIUS
			params.shape = edge_shape
			params.transform = Transform2D(delta.angle() + PI * 0.5, mid)
			var e_hits := space_state.intersect_shape(params, _MAX_HITS_PER_QUERY)
			_warn_if_truncated(e_hits, "edge", e_idx, t)
			for h in e_hits:
				var collider: Object = h.collider
				var seen = hit_edge.get(e_idx)
				if seen != null and seen.has(collider):
					continue
				step_contacts.append([
					true, e_idx, collider,
					state.edge_damage[e_idx] if e_idx < state.edge_damage.size() else 0.0,
					_edge_speed_at(state, i, e)])
		_resolve_step_contacts(step_contacts, t, hit_particle, hit_edge, events)
	_stable_sort(events, graph)
	return events


## Anti-double-dip (#785): per substep, a target takes at most ONE blade-element
## contact — the highest-damage one, never a sum. Every contender is marked
## contacted (so it cannot re-hit the same target on a later substep) but only
## the winner emits a [BladeHitEvent].
##
## This bounds the COUNTING RULE itself, which is what `combat_system.md`'s
## "tame runaway with the scalars, never the counting rule" asks for: a
## degree-6 hub deals vertex damage, not vertex + 6x edge damage, and a target
## straddled by two narrow-angled capsules takes the higher of the two.
##
## Ranking is on the raw damage COEFFICIENT, with contact speed as the
## tiebreak, NOT on the post-curve landed number: the speed curve
## ([method BladeState.speed_damage_multiplier]) needs the wielder's
## [StatBoard], which this module deliberately does not take, and the curve is
## monotonic in speed so the two orderings only ever differ between elements
## whose coefficients already differ AND whose speeds run the other way — a
## corner this rule does not need to be exact about, since its job is to cap a
## count, not to pick a maximum to the last decimal. A full tie resolves to the
## first contender in scan order (particles before edges, ascending index),
## which is fully deterministic.
static func _resolve_step_contacts(
		step_contacts: Array,
		t: float,
		hit_particle: Dictionary,
		hit_edge: Dictionary,
		events: Array[BladeHitEvent]) -> void:
	if step_contacts.is_empty():
		return
	var best: Dictionary = {}  # collider -> the winning contact tuple
	for c in step_contacts:
		var collider: Object = c[2]
		var seen: Dictionary = hit_edge if c[0] else hit_particle
		var per_element: Dictionary = seen.get_or_add(c[1], {})
		per_element[collider] = true
		var incumbent = best.get(collider)
		if incumbent == null:
			best[collider] = c
			continue
		if float(c[3]) > float(incumbent[3]):
			best[collider] = c
		elif is_equal_approx(float(c[3]), float(incumbent[3])) \
				and float(c[4]) > float(incumbent[4]):
			best[collider] = c
	for c in step_contacts:
		if best.get(c[2]) != c:
			continue
		if c[0]:
			events.append(BladeHitEvent.new(t, -1, int(c[1]), c[2], float(c[4])))
		else:
			events.append(BladeHitEvent.new(t, int(c[1]), -1, c[2], float(c[4])))


## True if nothing at all overlaps the blade's bounding box this substep — the
## broad-phase reject. One query, `_MAX_HITS_PER_QUERY` irrelevant (we only ask
## whether the count is zero, so the cap is 1).
static func _is_region_empty(
		space_state: PhysicsDirectSpaceState2D,
		params: PhysicsShapeQueryParameters2D,
		broad_shape: RectangleShape2D,
		positions: PackedVector2Array,
		max_radius: float) -> bool:
	if positions.is_empty():
		return true
	var lo := positions[0]
	var hi := positions[0]
	for p in positions:
		lo = lo.min(p)
		hi = hi.max(p)
	var pad := max_radius + _EDGE_RADIUS + _BROAD_PHASE_MARGIN
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)
	broad_shape.size = hi - lo
	params.shape = broad_shape
	params.transform = Transform2D(0.0, (lo + hi) * 0.5)
	return space_state.intersect_shape(params, 1).is_empty()


## Total order over [param events] — see the class docstring. `t` is the
## gameplay-meaningful primary key; a tie (two colliders newly hit in the
## SAME query, whose relative order Godot does not define) breaks on
## [member SkillNode.stable_id], read through [param graph] so a node added
## straight to the containers (id still 0) forces the mint rather than
## silently tying on zeroes (`.claude/rules/graph.md`). A further tie
## (same `t`, same target — a particle and an edge both landing on one
## collider in the same substep) breaks on element kind then index, which
## is already fully deterministic since the outer scan loops in fixed order.
static func _stable_sort(events: Array[BladeHitEvent], graph: Graph) -> void:
	events.sort_custom(func(a: BladeHitEvent, b: BladeHitEvent) -> bool:
		if a.t != b.t:
			return a.t < b.t
		if graph != null:
			var a_id := graph.get_stable_id(a.target as SkillNode)
			var b_id := graph.get_stable_id(b.target as SkillNode)
			if a_id != b_id:
				return a_id < b_id
		if a.is_edge_hit() != b.is_edge_hit():
			return b.is_edge_hit()  # particles before edges, deterministically
		return _element_idx(a) < _element_idx(b))


static func _element_idx(ev: BladeHitEvent) -> int:
	return ev.edge_idx if ev.is_edge_hit() else ev.particle_idx


## Contact speed for particle [param p_idx] at sample index [param i] —
## [member BladeState.speed_history][i][p_idx], the physics-rate value the
## LAST substep of that sample interval produced (#779). Defensive against a
## state built before this landed (or a fixture that skipped BladeSim.simulate
## entirely): an out-of-range history or particle index reads 0.0 rather than
## crashing the scan.
static func _speed_at(state: BladeState, i: int, p_idx: int) -> float:
	if i >= state.speed_history.size():
		return 0.0
	var step_speeds := state.speed_history[i]
	if p_idx >= step_speeds.size():
		return 0.0
	return step_speeds[p_idx]


## Contact speed for an EDGE at sample index [param i] — the MEAN of its two
## endpoints' speeds, which is the speed of the segment's midpoint under rigid
## motion and so the honest "how fast did this edge arrive" figure.
##
## The mean is also what keeps #785's NOTES true without a flag: a
## pivot-adjacent edge has one endpoint pinned at the pivot (speed 0), so its
## mean speed is roughly half its outer vertex's, and under #779's curve it
## earns almost nothing. "Edges are inert near the handle" survives as an
## emergent property of the geometry rather than a carve-out.
static func _edge_speed_at(state: BladeState, i: int, e: Vector2i) -> float:
	return 0.5 * (_speed_at(state, i, e.x) + _speed_at(state, i, e.y))
