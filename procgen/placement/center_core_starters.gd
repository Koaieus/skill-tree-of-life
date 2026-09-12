@tool
class_name CenterCoreStarters
extends StarterPlacement

## Places the first contender dead centre and fills the rest with
## rejection-sampled random anchors inside the shape mask — the single-player
## default lifted off the legacy branch `GraphProcgen` special-cased before
## #742 (`_place_random_starters`, issue #15) into a real [StarterPlacement]
## sibling of [CampAnnulusStarters] (#551).
##
## [b]"Center" names the geometry, not a camp.[/b] Every anchor after the
## first is filled by rejection-sampling a random point inside the shape
## mask — but since #758, the rejection radius is CAMP-AWARE via
## [method StarterPlacement.required_spacing]: two starters in different
## camps must clear the full `viability_radius * min_dist` ask on every
## attempt (a floor that never degrades — the fix for "either an overpowered
## enemy finds you immediately, or nothing finds you"), while two starters
## in the SAME camp only need half that, degrading toward `min_dist` across
## the retry loop exactly the way the legacy function's `min_sq` rejection
## did — the spacing SHRINKS toward `min_dist` across tries rather than
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
	_stamp_camp(center, 0)
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

	# Per-index camp lookup (#758): `camp_sizes` walked in order gives camp 0's
	# members first, then camp 1's, ... — the same participant-order contract
	# [method plan]'s own docstring pins, so `camp_of[i]` is which camp the
	# i-th returned point belongs to.
	var camp_of := _camp_lookup(camp_sizes)

	var tries := maxi(1, max_tries)
	for i in range(1, total):
		var my_camp: int = camp_of[i]
		var placed := false
		for attempt in tries:
			var p := Vector2(
					rng.randf_range(bounds.position.x, bounds.end.x),
					rng.randf_range(bounds.position.y, bounds.end.y))
			if not mask.contains(p):
				continue
			var ok := true
			for j in out.size():
				# The placed point's OWN camp, not `camp_of[j]`: `j` indexes
				# the output and `camp_of` the participant slots, and an
				# unplaceable contender is skipped below rather than
				# substituted — so after one skip the two disagree and a
				# cross-camp pair would be compared on the halved same-camp
				# ask. See [method StarterPlacement._stamp_camp].
				var same_camp := camp_of_placed(out, j) == my_camp
				var required := required_spacing(min_dist, attempt, tries, same_camp)
				if p.distance_squared_to(out[j].position) < required * required:
					ok = false
					break
			if not ok:
				continue
			var new_sp := StartingPoint.new()
			new_sp.position = p
			new_sp.id = StringName("enemy_%d" % (i - 1))
			_stamp_camp(new_sp, my_camp)
			out.append(new_sp)
			placed = true
			break
		if not placed:
			push_warning(
					"CenterCoreStarters: couldn't place random starter %d after %d tries — "
					% [i - 1, tries] + "viability_radius too large for shape/anchor density?")
	return out


## `camp_of[i]` is the camp index the i-th [method plan] return slot belongs
## to, per [param camp_sizes] walked camp 0 first — mirrors the `camp_of`
## bucketing every caller building `camp_sizes` already does one level up
## (`scenes/procgen_play_sandbox.gd`'s `_camp_sizes`), just inverted: that one
## counts participants per camp, this one answers "which camp is slot i in".
static func _camp_lookup(camp_sizes: Array[int]) -> Array[int]:
	var lookup: Array[int] = []
	for camp_idx in camp_sizes.size():
		for _n in maxi(0, camp_sizes[camp_idx]):
			lookup.append(camp_idx)
	return lookup
