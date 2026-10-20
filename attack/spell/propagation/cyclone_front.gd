@tool
class_name CycloneFront
extends PayloadExtension

## Cyclone's carried front: the five per-payload facts only the curl walk
## stamps and reads, kept off the baseline [CastSpell]. Read it as
## [code]payload.extra(CycloneFront.ID) as CycloneFront.State[/code]; a payload
## without one reads the defaults ([BacktrackFilter] allows, [CycleCondition]
## is false, the event's turn sign is 0).
##
## [method mint] copies the [PropagationPick]'s stamps verbatim — the spread
## decided them. [method merge] is the convergence re-stamp: closing ORs and
## dominates, the lineage is the closer's (else the strongest front's), and the
## heading is the strength-weighted mean of the arriving fronts. Strength is
## [member State.weight], which [CycloneReducer] stamps from each incident's
## damage before merging; unstamped (another reducer), every front weighs 0
## and the first incident's lineage and heading survive.

const ID := &"cyclone"


## One front's carried state.
class State extends PayloadState:
	## The front's direction of travel, normalised; [CycloneSpread] measures its
	## turn ranking against it. A merge writes the strength-weighted mean.
	## [constant Vector2.ZERO] = unset (the seed, or a head-on cancel the
	## merge resolved): the spread falls back to the predecessor, then source.
	var arrival_bearing: Vector2 = Vector2.ZERO
	## The rank coefficient this ONE arc was minted with (closing gain folded
	## in): the VFX draws the spine heavier than the offshoots off it. Per-arc
	## telemetry — a merge resets it to 1.0; the resolver reads the per-arc
	## values off the incidents.
	var arrival_share: float = 1.0
	## +1 clockwise, -1 counter-clockwise, 0 at the seed. Constant for a cast.
	var turn_sign: float = 0.0
	## The nodes [BacktrackFilter] vetoes this front's next step back into.
	## Empty = free (a cycle-closing hop clears it).
	var came_from: Array[SkillNode] = []
	## True when the hop that made this payload landed on its own lineage's
	## trail — read by [CycleCondition], ORed across a merge.
	var closed_cycle: bool = false
	## The incident's damage, stamped by [CycloneReducer] just before a merge;
	## weighs the heading and picks the surviving lineage. 0 outside a merge.
	var weight: float = 0.0


func _init() -> void:
	id = ID


## The seed carries no heading: [CycloneSpread] measures the opening fan from
## the cast-from node, the same direction a seeded bearing would point.
func seed(_ctx: PropagationContext) -> PayloadState:
	return _state()


func mint(_parent: PayloadState, pick: PropagationPick, _lctx: LandingContext,
		_hop_index: int) -> PayloadState:
	var out := _state()
	out.arrival_share = pick.share
	out.arrival_bearing = pick.arrival_bearing
	out.turn_sign = pick.turn_sign
	out.closed_cycle = pick.closed_cycle
	out.came_from = pick.came_from.duplicate()
	return out


## Closing DOMINATES: [member State.closed_cycle] ORs, and a closer's lineage
## (the strongest closer's) wins whole with a cleared [member State.came_from];
## otherwise the strongest front's set survives. Ties go to the earlier state.
func merge(states: Array[PayloadState]) -> PayloadState:
	var winner := states[0] as State
	var closer: State = null
	for s: PayloadState in states:
		var f := s as State
		if f.weight > winner.weight:
			winner = f
		if f.closed_cycle and (closer == null or f.weight > closer.weight):
			closer = f
	var lineage: State = closer if closer != null else winner
	var out := _state()
	out.turn_sign = lineage.turn_sign
	out.closed_cycle = closer != null
	if closer == null:
		out.came_from = lineage.came_from.duplicate()
	out.arrival_bearing = _combined_bearing(states, lineage)
	return out


## The merged front's heading: each front's normalised direction of travel,
## weighted by the strength it brought. Owner's spec, verbatim: [i]"from this
## side, this strength; from that side, that strength; combined: this strength
## that direction"[/i]. Two fronts meeting head-on cancel to zero — a real
## event, not a degenerate one — and the surviving lineage's own heading is
## kept, so the storm carries on the way the winner was going.
static func _combined_bearing(states: Array[PayloadState], lineage: State) -> Vector2:
	var bearing := Vector2.ZERO
	for s: PayloadState in states:
		var heading := (s as State).arrival_bearing
		if heading == Vector2.ZERO:
			continue
		bearing += heading.normalized() * maxf((s as State).weight, 0.0)
	return bearing.normalized() if bearing != Vector2.ZERO else lineage.arrival_bearing


func _state() -> State:
	var s := State.new()
	s.template = self
	return s
