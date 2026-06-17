class_name BladeHitScan
extends RefCounted

## Pure hit-detection over a BladeTrajectory.
##
## `targets`: Array of [Vector2 position, float radius, Object payload]. The
## payload is opaque to the scan (typically a SkillNode); it round-trips
## untouched into each emitted BladeHitEvent.
##
## Per-element-per-target dedup: each blade element (particle or edge) can
## hit each target at most once across the whole sweep, emitting on first
## contact.
static func scan(
		trajectory: BladeTrajectory,
		state: BladeState,
		targets: Array) -> Array[BladeHitEvent]:
	var events: Array[BladeHitEvent] = []
	if trajectory.samples.size() < 2:
		return events
	# element_idx → { target_payload: true }
	var hit_particle: Dictionary = {}
	var hit_edge: Dictionary = {}
	var samples := trajectory.samples
	var dt := trajectory.sample_dt
	var particle_count := state.positions.size()
	var edges := state.edges
	var radii := state.radii
	for i in range(1, samples.size()):
		var t: float = float(i) * dt
		var prev := samples[i - 1]
		var curr := samples[i]
		# Particle hits — swept segment vs. each target circle.
		for p_idx in particle_count:
			var r: float = radii[p_idx]
			for tgt in targets:
				var tpos: Vector2 = tgt[0]
				var trad: float = tgt[1]
				var payload = tgt[2]
				var seen_for_p = hit_particle.get(p_idx, null)
				if seen_for_p != null and seen_for_p.has(payload):
					continue
				if _segment_circle_hit(prev[p_idx], curr[p_idx], tpos, r + trad):
					if seen_for_p == null:
						seen_for_p = {}
						hit_particle[p_idx] = seen_for_p
					seen_for_p[payload] = true
					events.append(BladeHitEvent.new(t, p_idx, -1, payload))
		# Edge hits — sampled endpoints, point-vs-segment proximity at
		# both boundaries of the sub-step. Sufficient at 120Hz sampling.
		for e_idx in edges.size():
			var e := edges[e_idx]
			for tgt in targets:
				var tpos: Vector2 = tgt[0]
				var trad: float = tgt[1]
				var payload = tgt[2]
				var seen_for_e = hit_edge.get(e_idx, null)
				if seen_for_e != null and seen_for_e.has(payload):
					continue
				var hit_now := _point_segment_dist_le(tpos, prev[e.x], prev[e.y], trad) \
						or _point_segment_dist_le(tpos, curr[e.x], curr[e.y], trad)
				if hit_now:
					if seen_for_e == null:
						seen_for_e = {}
						hit_edge[e_idx] = seen_for_e
					seen_for_e[payload] = true
					events.append(BladeHitEvent.new(t, -1, e_idx, payload))
	return events


static func _segment_circle_hit(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	return _point_segment_dist_le(c, a, b, r)


static func _point_segment_dist_le(p: Vector2, a: Vector2, b: Vector2, r: float) -> bool:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	var t := 0.0
	if ab_len_sq > 1e-12:
		t = clampf(ab.dot(p - a) / ab_len_sq, 0.0, 1.0)
	var closest := a + ab * t
	return (closest - p).length_squared() <= r * r
