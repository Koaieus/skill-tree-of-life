class_name BladeHitScan
extends RefCounted

## Hit detection over a BladeTrajectory via the 2D physics server.
##
## Each sub-step, every blade particle is queried as a circle at its
## sampled position, and every blade edge as a thin rectangle along its
## sampled endpoints. The physics server returns whatever colliders
## overlap — this module doesn't encode target geometry at all; targets
## just publish a CollisionShape2D and we get hits back.
##
## Determinism: queries are a pure function of (sim positions, world
## state) [b]only while no query hits [constant _MAX_HITS_PER_QUERY][/b] —
## see that constant. As long as the world state is itself sim-driven and
## the cap is never reached, replays reproduce the same events. Ghost
## previews work the same way because the blade never enters the physics
## world — only the query shapes do.
##
## Note this purity is over a SINGLE machine. Result ORDER within one
## query is broadphase-dependent, so the same claim across peers is
## stronger than anything Godot guarantees. That is why melee cannot be
## replayed from attack intent alone (`docs/domain/multiplayer-sync-model.md`).
##
## Per-element-per-collider dedup: each particle/edge emits at most one
## event per collider across the whole sweep, on first contact.

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

static func scan(
		trajectory: BladeTrajectory,
		state: BladeState,
		space_state: PhysicsDirectSpaceState2D,
		collision_mask: int = 0xFFFFFFFF,
		exclude: Array[RID] = []) -> Array[BladeHitEvent]:
	var events: Array[BladeHitEvent] = []
	if space_state == null or trajectory.samples.size() < 2:
		return events
	# element_idx → { collider: true }
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
	# Reused across edge queries; size/transform get rewritten each step.
	var edge_shape := RectangleShape2D.new()

	var params := PhysicsShapeQueryParameters2D.new()
	params.collision_mask = collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = exclude

	for i in range(1, samples.size()):
		var t: float = float(i) * dt
		var curr := samples[i]
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
				if seen == null:
					seen = {}
					hit_particle[p_idx] = seen
				seen[collider] = true
				events.append(BladeHitEvent.new(t, p_idx, -1, collider))
		for e_idx in edges.size():
			var e := edges[e_idx]
			var a := curr[e.x]
			var b := curr[e.y]
			var delta := b - a
			var length := delta.length()
			if length < 1e-4:
				continue
			edge_shape.size = Vector2(length, 1.0)
			params.shape = edge_shape
			params.transform = Transform2D(delta.angle(), (a + b) * 0.5)
			var e_hits := space_state.intersect_shape(params, _MAX_HITS_PER_QUERY)
			_warn_if_truncated(e_hits, "edge", e_idx, t)
			for h in e_hits:
				var collider: Object = h.collider
				var seen = hit_edge.get(e_idx)
				if seen != null and seen.has(collider):
					continue
				if seen == null:
					seen = {}
					hit_edge[e_idx] = seen
				seen[collider] = true
				events.append(BladeHitEvent.new(t, -1, e_idx, collider))
	return events
