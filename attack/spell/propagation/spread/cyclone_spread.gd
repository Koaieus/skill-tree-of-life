@tool
class_name CycloneSpread
extends PropagationSpread

## Cyclone's curl (#703, superseding the parity design of #699). Ranks the
## filtered candidates by the turn the front makes to reach them — measured from
## the edge it arrived on, in one fixed rotational direction — and picks one
## child per rank, carrying a decaying share of the incoming damage. The share
## rides the [PropagationPick]; [method PropagationConfig.mint] is where the
## damage is actually split (#852).
##
## [b]The whole spell is three numbers.[/b] Rank 1 is the sharpest turn, so it
## hugs the face the front is circling; ranks 2 and 3 are wider turns that
## radiate outward. Give them coefficients whose SUM exceeds 1 while each is
## individually BELOW 1 and you get the storm: energy grows globally, decays per
## thread, and therefore concentrates only where the geometry folds threads back
## together. Circulation reinforces, offshoots diminish. Nothing detects a
## cycle to make that happen — it is what a weighted walk on a planar graph
## does.
##
## Modelled as a linear operator on directed edges, growth per wave is its
## spectral radius, and it collapses to two readings:
## [codeblock]
## rho(any lone ring)      = c_1          # regardless of LENGTH or PARITY
## rho(dense triangulated) → sum(c_r)
## [/codeblock]
## so the authoring condition is [b]c_1 < 1 < sum(c_r)[/b]: a lone ring cannot
## sustain itself, a triangulated patch can. Measured: every tree is exactly
## 0.000, every lone ring (triangle through hexagon alike) 0.650, a hex wheel
## 1.159, a 37-node triangular lattice 1.326. The spell stopped typing terrain
## by "is it cyclic" and started typing it by "is it two-dimensional", which is
## the point — parity was never a designed property, only the residue of a
## rotation-blind fan.
##
## [b]Why a ranked fan and not a face-trace.[/b] Taking only rank 1 is the
## next-edge permutation, whose orbits are the embedding's faces — elegant, and
## wrong for this spell: it necessarily assigns one arm to the OUTER face, so a
## triangle reads as two arms colliding rather than one storm turning. A ranked
## fan has no such arm. Verified on a hex wheel: all six arms off the hub trace
## same-signed faces, i.e. they co-rotate, which is the wheel the spell is for.
##
## [b]Closing a loop boosts the coefficient[/b] ([member closing_gain]) rather
## than merely lighting up [CycleCondition]. The crit is sparkle on the
## landing; the gain feeds FORWARD, so a ring that closes gets sustain and a
## lone triangle is worth killing over instead of fizzling at c_1 per hop.
## Owner call 2026-09-01.
##
## Every knob is an export because the owner tunes them live — the spell
## playground re-reads spread exports on each Cast (`playground_panel.gd`).


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


func select(
		current: SkillNode,
		eligible: Array[SkillNode],
		payload: CastSpell,
		_ctx: PropagationContext) -> Array[PropagationPick]:
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
		# outvote a short one when CycloneReducer averages several of them.
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
## [member CastSpell.arrival_bearing] first, because a merged front's heading is
## the weighted mean of everything that arrived and NOT the one predecessor the
## reducer kept; falling back to [member CastSpell.predecessor] would quietly
## discard the other fronts' contribution to which way the storm is now turning.
## The seed has neither, so it measures from the cast-from node, which is what
## gives the opening fan a direction instead of firing symmetrically.
func _arrival_position(current_node: SkillNode, payload: CastSpell) -> Vector2:
	if payload.arrival_bearing != Vector2.ZERO:
		return current_node.global_position - payload.arrival_bearing
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
