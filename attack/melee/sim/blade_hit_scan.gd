class_name BladeHitScan
extends RefCounted

## Hit detection over a BladeTrajectory via the 2D physics server: every particle
## as a circle, every edge as a swept capsule trimmed to its endpoints' rims,
## each element emitting at most one event per collider (first contact). Output
## is stable-sorted by `t` then [member SkillNode.stable_id]. Reproducible only
## while no query hits [constant _MAX_HITS_PER_QUERY].
## See docs/domain/melee-blade-internals.md "BladeHitScan determinism".

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
const EDGE_RADIUS := 0.5


## One resolve's sweep, held open across samples (#801).
##
## [b]Why this is an object and not a loop.[/b] The interleaved resolve scans
## ONE sample, lands what it found, and only then steps on — so the dedup
## dictionaries, the query shapes and the params have to outlive a single
## sample. They are exactly the state a whole-trajectory `scan` used to keep on
## its stack. Holding them here is what makes the per-element-per-collider
## counting rule span the whole sweep even when the trajectory is re-baked
## underneath it: a vertex that already hit a collider while driven does not hit
## it again while coasting.
##
## [method BladeHitScan.scan] is this class over a finished trajectory, so there
## is one implementation of the query geometry, not two.
class Sweep extends RefCounted:
	var _state: BladeState
	var _space_state: PhysicsDirectSpaceState2D
	var _graph: Graph
	var _params: PhysicsShapeQueryParameters2D
	var _particle_shapes: Array[CircleShape2D] = []
	var _edge_shape := CapsuleShape2D.new()
	var _broad_shape := RectangleShape2D.new()
	var _max_radius: float = 0.0
	var _broad_phase: bool
	# element key -> { collider: true }. First contact emits; every later
	# contact between the same element and the same collider is silent, for the
	# whole sweep.
	var _hit_particle: Dictionary = {}
	var _hit_edge: Dictionary = {}

	func _init(
			state: BladeState,
			space_state: PhysicsDirectSpaceState2D,
			graph: Graph,
			collision_mask: int = SkillNode.GAMEPLAY_QUERY_MASK,
			exclude: Array[RID] = [],
			broad_phase: bool = true) -> void:
		_state = state
		_space_state = space_state
		_graph = graph
		_broad_phase = broad_phase
		for p in state.positions.size():
			var c := CircleShape2D.new()
			c.radius = state.radii[p]
			_particle_shapes.append(c)
			_max_radius = maxf(_max_radius, state.radii[p])
		_edge_shape.radius = EDGE_RADIUS
		_params = PhysicsShapeQueryParameters2D.new()
		_params.collision_mask = collision_mask
		_params.collide_with_areas = true
		_params.collide_with_bodies = false
		_params.exclude = exclude

	## Query one pose and return the contacts it newly makes, in this file's
	## total order (see [method BladeHitScan._stable_sort]). `speeds` is the
	## per-particle contact speed for this sample — [BladeState.speed_history]'s
	## entry for it — passed explicitly rather than read off the state, because
	## a re-baked chunk rebuilds that history chunk-local (#801).
	##
	## A DESTROYED vertex is not queried at all, and neither is an edge touching
	## one or a severed edge: a dead element is not swinging, so it mints no
	## event to be refused later. That is where the interleave's "a pop swing
	## costs FEWER physics queries" comes from.
	func scan_sample(
			t: float,
			curr: PackedVector2Array,
			speeds: PackedFloat32Array) -> Array[BladeHitEvent]:
		var events: Array[BladeHitEvent] = []
		if _space_state == null or curr.is_empty():
			return events
		# Broad phase (#785): ONE query per sample over the blade's whole
		# bounding box. A blade sweeping empty space — the overwhelmingly
		# common sample at 100 vertices / 200 edges — then costs 1 query
		# instead of ~300. The box is a strict superset of every narrow-phase
		# shape (particle disks are inside `max_radius` of a position, edge
		# capsules are inside the convex hull of two positions plus
		# `EDGE_RADIUS`), so turning this off can only ADD cost, never
		# change the event set — which is what `broad_phase` exists to let a
		# benchmark verify.
		if _broad_phase and BladeHitScan._is_region_empty(
				_space_state, _params, _broad_shape, curr, _max_radius):
			return events
		var removed_v := _state.removed_vertices
		for p_idx in _particle_shapes.size():
			if removed_v.has(p_idx):
				continue
			_params.shape = _particle_shapes[p_idx]
			_params.transform = Transform2D(0.0, curr[p_idx])
			var p_hits := _space_state.intersect_shape(_params, _MAX_HITS_PER_QUERY)
			BladeHitScan._warn_if_truncated(p_hits, "particle", p_idx, t)
			for h in p_hits:
				var collider: Object = h.collider
				var seen: Dictionary = _hit_particle.get_or_add(p_idx, {})
				if seen.has(collider):
					continue
				seen[collider] = true
				events.append(BladeHitEvent.new(
						t, p_idx, -1, collider, _speed_of(speeds, p_idx)))
		var edges := _state.edges
		var radii := _state.radii
		for e_idx in edges.size():
			if _state.removed_edges.has(e_idx):
				continue  # severed (#781) — a gone edge collides with nothing
			var e := edges[e_idx]
			if removed_v.has(e.x) or removed_v.has(e.y):
				continue  # hanging off a corpse (#801) — not swinging either
			var a := curr[e.x]
			var b := curr[e.y]
			var delta := b - a
			var length := delta.length()
			# The capsule covers the segment MINUS the two endpoint hitbox disks
			# (#785, kept by ADR 0005 as geometry rather than offence): it starts at
			# one vertex's rim and stops at the other's, so a target sitting ON a
			# vertex is inside that vertex's own circle and the hub deals vertex
			# damage, not vertex + one-per-incident-edge. Short edges whose
			# endpoints' disks already overlap have no exposed span at all and
			# contribute nothing.
			var trimmed := length - radii[e.x] - radii[e.y]
			if trimmed < 1e-4:
				continue
			var dir := delta / length
			var mid := a + dir * (radii[e.x] + trimmed * 0.5)
			_edge_shape.height = trimmed + 2.0 * EDGE_RADIUS
			_params.shape = _edge_shape
			_params.transform = Transform2D(delta.angle() + PI * 0.5, mid)
			var e_hits := _space_state.intersect_shape(_params, _MAX_HITS_PER_QUERY)
			BladeHitScan._warn_if_truncated(e_hits, "edge", e_idx, t)
			for h in e_hits:
				var collider: Object = h.collider
				var seen: Dictionary = _hit_edge.get_or_add(e_idx, {})
				if seen.has(collider):
					continue
				seen[collider] = true
				# A structural contact, not a damaging one (ADR 0005): the event
				# exists so an edge can be stopped by, and eventually broken against,
				# a bunker (#781). It carries no damage coefficient — there is no
				# `edge_damage` — and it never reaches the spike gate.
				events.append(BladeHitEvent.new(
						t, -1, e_idx, collider,
						0.5 * (_speed_of(speeds, e.x) + _speed_of(speeds, e.y))))
		BladeHitScan._stable_sort(events, _graph)
		return events

	static func _speed_of(speeds: PackedFloat32Array, idx: int) -> float:
		return speeds[idx] if idx < speeds.size() else 0.0


## Scan a finished trajectory — [Sweep] driven over every sample, which is what
## the AI rollout, the benchmarks and the characterization fixtures want. The
## live resolve drives the [Sweep] itself, one sample at a time (#801).
##
## Concatenating per-sample batches is byte-identical to sorting the whole set
## afterwards: `t` is the comparator's primary key and it is constant within a
## sample, so the batches are already the total order's blocks.
static func scan(
		trajectory: BladeTrajectory,
		state: BladeState,
		space_state: PhysicsDirectSpaceState2D,
		graph: Graph,
		collision_mask: int = SkillNode.GAMEPLAY_QUERY_MASK,
		exclude: Array[RID] = [],
		broad_phase: bool = true) -> Array[BladeHitEvent]:
	var events: Array[BladeHitEvent] = []
	if space_state == null or trajectory.samples.size() < 2:
		return events
	var sweep := Sweep.new(
			state, space_state, graph, collision_mask, exclude, broad_phase)
	var dt := trajectory.sample_dt
	for i in range(1, trajectory.samples.size()):
		events.append_array(sweep.scan_sample(
				float(i) * dt, trajectory.samples[i], speeds_at(state, i)))
	return events


## [BladeState.speed_history]'s entry for sample [param i], or an empty array
## when the state was built without one (a fixture that skipped
## [method BladeSim.simulate_range] entirely) — [method Sweep._speed_of] then
## reads 0.0 rather than the scan crashing.
static func speeds_at(state: BladeState, i: int) -> PackedFloat32Array:
	if i < 0 or i >= state.speed_history.size():
		return PackedFloat32Array()
	return state.speed_history[i]


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
	var pad := max_radius + EDGE_RADIUS + _BROAD_PHASE_MARGIN
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
