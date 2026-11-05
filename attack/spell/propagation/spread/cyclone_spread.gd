@tool
class_name CycloneSpread
extends PropagationSpread

## Cyclone's curl. Ranks the filtered candidates by the turn the front makes to
## reach them (one fixed rotational direction) and picks one child per rank,
## each carrying a decaying share of the incoming damage; the split itself
## happens in [method PropagationConfig.mint]. Authoring condition
## `c_1 < 1 < sum(c_r)`. Every knob is an export (tuned live in the playground).
## See docs/domain/spell-propagation.md "CycloneSpread: the curl".


## Shortest ring worth remembering. Below this the "cycle" is the reversal edge
## itself, which is a footprint the lineage would ping-pong on forever.
const MIN_RING := 3

## Damage share picked at each turn-rank: index 0 is the sharpest turn. Entries
## beyond the candidate count are ignored; a rank with no coefficient is not
## travelled at all, so the array length doubles as the fan width.
@export var rank_coefficients := PackedFloat32Array([0.70, 0.40, 0.20])

## Extra multiplier on a hop that CLOSES a loop. This is the sustain term: at
## 1.0 a lone triangle decays at c_1 per hop and fizzles; above it the ring
## feeds itself and the triangle becomes a kill.
@export var closing_gain: float = 1.35

## Which way the storm turns. Flipping it mirrors every cast; it is a handedness
## and not a balance knob.
@export var clockwise: bool = true


func select(eligible: Array[SkillNode], lctx: LandingContext) -> Array[PropagationPick]:
	var current := lctx.node
	var payload := lctx.payload
	var out: Array[PropagationPick] = []
	if eligible.is_empty() or rank_coefficients.is_empty():
		return out
	var ranked := Curl.rank(
			_arrival_position(current, payload), current, eligible, clockwise)
	for rank_index in ranked.size():
		if rank_index >= rank_coefficients.size():
			break
		var coefficient := rank_coefficients[rank_index]
		if coefficient <= 0.0:
			continue
		var nb: SkillNode = ranked[rank_index]
		var pick := PropagationPick.new()
		pick.node = nb
		# Normalised: a heading, not a displacement, so a long edge cannot
		# outvote a short one when CycloneFront.merge averages several of them.
		pick.arrival_bearing = (nb.global_position - current.global_position).normalized()
		# `payload.visited` is the PARENT's trail: the destination is not on it
		# yet (the mint appends it), so `find` really asks "have we been here".
		var idx := payload.visited.find(nb)
		if idx < 0:
			pick.closed_cycle = false
			var arrived: Array[SkillNode] = [payload.current_node]
			pick.came_from = arrived
		else:
			pick.closed_cycle = true
			pick.lineage_override = closed_ring(payload.visited, idx)
			coefficient *= closing_gain
		# The share scales whatever `hop_damage` produces rather than replacing
		# it — the mint applies the progression first, then multiplies by this
		# — so an authored ramp still composes with the curl's split.
		#
		# Stamped, not derivable (#704): once `damage` has been multiplied the
		# coefficient is gone. CycloneReducer SUMS every incident and the crit
		# multiplies again at landing, so no downstream reader can invert a
		# landed amount back to the rank that produced it; the VFX layer needs
		# it to draw the spine heavier than the offshoots, which is the whole
		# mechanic. `closing_gain` is already folded in, deliberately — a
		# closing rank-1 arc really is carrying more than an ordinary one.
		pick.share = coefficient
		pick.turn_sign = 1.0 if clockwise else -1.0
		out.append(pick)
	return out


## Where the front came FROM, as a position — the only thing the ranking needs.
##
## [member CycloneFront.State.arrival_bearing] first, because a merged front's
## heading is the weighted mean of everything that arrived and NOT the one
## predecessor the reducer kept; falling back to [member CastSpell.predecessor]
## would quietly discard the other fronts' contribution to which way the storm
## is now turning. The seed has neither, so it measures from the cast-from
## node, which is what gives the opening fan a direction instead of firing
## symmetrically.
func _arrival_position(current_node: SkillNode, payload: CastSpell) -> Vector2:
	var front := payload.extra(CycloneFront.ID) as CycloneFront.State
	if front != null and front.arrival_bearing != Vector2.ZERO:
		return current_node.global_position - front.arrival_bearing
	if payload.predecessor != null:
		return payload.predecessor.global_position
	if payload.source != null:
		return payload.source.global_position
	return current_node.global_position


## The ring a closing hop just walked, ending at the landed node — which is
## where the front now stands, and where the next hop measures its own trail
## from. [param idx] is the landed node's previous position in [param trail].
##
## Normally that is the trail's suffix from `idx`: the pre-cycle tail is
## discarded and what is left is exactly the loop. The one hop that can measure
## under [constant MIN_RING] is a step back onto the node one behind, whose
## forward arc is a single edge — but the cycle it closes is the complementary
## arc, the whole ring the other way, so rotate rather than truncate.
##
## [b]Never append.[/b] An earlier cut kept the parent trail and appended the
## landed node on the short branch, which put a node in the trail twice; two
## hops later [method Array.find] returned the FIRST occurrence and the guard
## waved through a vertex-repeating closed walk. Truncating on every close is
## what keeps the trail all-distinct, and the all-distinct trail is what makes
## every [CycleCondition] crit a real simple cycle of length >= 3.
static func closed_ring(trail: Array[SkillNode], idx: int) -> Array[SkillNode]:
	var landed: SkillNode = trail[idx]
	var forward: Array[SkillNode] = trail.slice(idx + 1)
	forward.append(landed)
	if forward.size() >= MIN_RING:
		return forward
	var complementary: Array[SkillNode] = trail.slice(idx + 1)
	complementary.append_array(trail.slice(0, idx + 1))
	return complementary if complementary.size() >= MIN_RING else forward


func get_description() -> String:
	return "Turns one way, splitting its power across the turn it can make."
