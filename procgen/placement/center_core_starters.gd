@tool
class_name CenterCoreStarters
extends StarterPlacement

## Places the first contender dead centre and fills the rest with
## rejection-sampled random anchors inside the shape mask — the single-player
## default lifted off the legacy branch `GraphProcgen` special-cased before
## #742 (`_place_random_starters`, issue #15) into a real [StarterPlacement]
## sibling of [CampAnnulusStarters] (#551).
##
## [b]"Center" names the geometry, not a camp.[/b] Camp STRUCTURE is ignored
## here — every anchor after the first is filled uniformly at random
## regardless of which camp it belongs to, because this placement exists for
## the single-player shape where there is exactly one human (dead centre) and
## every other contender is an AI opponent. [member StarterPlacement.viability_radius]
## still applies, degraded via [method StarterPlacement.degrade_spacing] over
## the retry loop exactly the way the legacy function's `min_sq` rejection did
## — only now the spacing SHRINKS toward `min_dist` across tries rather than
## rejecting forever, so a crowded shape still terminates.
##
## Return order is still PARTICIPANT order (index 0 = the centred contender),
## the same load-bearing contract [CampAnnulusStarters] holds.


func plan(
		camp_sizes: Array[int],
		_radius: float,
		min_dist: float,
		rng: RandomNumberGenerator,
		mask: ShapeMask = null,
		max_tries: int = 200,
) -> Array[StartingPoint]:
	var out: Array[StartingPoint] = []
	var total := 0
	for n in camp_sizes:
		total += maxi(0, n)
	if total <= 0:
		push_warning("CenterCoreStarters: camp_sizes is empty/all-zero — no starters placed")
		return out

	var center := StartingPoint.new()
	center.position = Vector2.ZERO
	center.id = &"core"
	out.append(center)
	if total == 1:
		return out

	if mask == null:
		push_warning("CenterCoreStarters: no shape mask — couldn't place %d random starter(s)" % (total - 1))
		return out
	var bounds := mask.aabb()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_warning("CenterCoreStarters: shape mask has no area — couldn't place %d random starter(s)" % (total - 1))
		return out

	var tries := maxi(1, max_tries)
	for i in range(1, total):
		var placed := false
		for attempt in tries:
			var p := Vector2(
					rng.randf_range(bounds.position.x, bounds.end.x),
					rng.randf_range(bounds.position.y, bounds.end.y))
			if not mask.contains(p):
				continue
			var required := degrade_spacing(min_dist, attempt, tries)
			var required_sq := required * required
			var ok := true
			for sp in out:
				if p.distance_squared_to(sp.position) < required_sq:
					ok = false
					break
			if not ok:
				continue
			var new_sp := StartingPoint.new()
			new_sp.position = p
			new_sp.id = StringName("enemy_%d" % (i - 1))
			out.append(new_sp)
			placed = true
			break
		if not placed:
			push_warning(
					"CenterCoreStarters: couldn't place random starter %d after %d tries — "
					% [i - 1, tries] + "viability_radius too large for shape/anchor density?")
	return out
