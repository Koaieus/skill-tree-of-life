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
## state). As long as the world state is itself sim-driven, replays
## reproduce the same events. Ghost previews work the same way because
## the blade never enters the physics world — only the query shapes do.
##
## Per-element-per-collider dedup: each particle/edge emits at most one
## event per collider across the whole sweep, on first contact.

const _MAX_HITS_PER_QUERY := 16

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
