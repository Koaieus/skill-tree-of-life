@tool
class_name RetractSpread
extends PropagationSpread

## Lodestone's out-and-back walk, over the [RetractFront] state the payload
## carries. Author it with [code]max_visits_per_node = 1[/code] and a hostile
## filter, so OUT is a BFS: depth k lands on wave k, fronts reaching one node
## merge, and the eligible set at depth k is exactly the hostile depth-k+1 ring.
##
## [b]OUT at depth k[/b]: records the node's parents and trail count in the
## cast's [RetractFront.Walk]; fans through [member outbound_spread] while
## k < [member depth], else hops in place. [b]In place[/b]: WAIT until the
## next wave is the turn wave [code]2·depth − k + 1[/code], where the hop is
## BACK — so every return reaches depth j on wave [code]2·depth − j + 1[/code]
## and returns meet in sync. [b]BACK at depth k > 0[/b]: per debuff d, passes
## [code]now_d − max(0, seen_d − load_d)[/code] (what landed plus up to load_d
## of the node's own), split over its parents by trail count, largest
## remainder ([Apportion]); one BACK pick per parent that gets anything.
## [b]BACK at the seed[/b] ends the cast. Self-picks and BACK picks name nodes
## the visit cap excluded — the resolver mints any pick a spread returns.

## How far out the tendrils go — the main power dial: the haul roughly
## doubles per ring. Tentative, easy to change.
@export_range(1, 8) var depth: int = 3

## How OUT picks among the next ring. Null = [FanAllSpread].
@export var outbound_spread: PropagationSpread = null

## The [RetractFront] this walks, by its [member PayloadExtension.id].
@export var front_id: StringName = RetractFront.ID

## The concept whose load floors every debuff's haul (Greed's).
const FLOOR_CONCEPT := &"greed"


func select(eligible: Array[SkillNode], lctx: LandingContext) -> Array[PropagationPick]:
	var out: Array[PropagationPick] = []
	var st := RetractFront.state_of(lctx.payload, front_id)
	if st == null:
		return out
	var k := st.depth
	match st.phase:
		RetractFront.Phase.OUT:
			_record(st.walk, lctx)
			if k < depth:
				for pick in _outbound().select(eligible, lctx):
					out.append(_as_out(pick, k + 1))
			if out.is_empty():
				out.append(_in_place(lctx, k))
		RetractFront.Phase.WAIT:
			out.append(_in_place(lctx, k))
		RetractFront.Phase.BACK:
			if k > 0:
				out.append_array(_returns(st, lctx))
	return out


## The wave a tendril at depth [param k] turns on.
func turn_wave(k: int) -> int:
	return 2 * depth - k + 1


## [param node]'s haul floor for [param d]: the cast's Greed load plus its
## load of d's own concept (Greed's floor is its load alone).
static func load_for(d: StatusDef, load: Dictionary) -> int:
	var concept := concept_of(d)
	var floor_ := int(load.get(FLOOR_CONCEPT, 0))
	return floor_ if concept == FLOOR_CONCEPT else floor_ + int(load.get(concept, 0))


static func concept_of(d: StatusDef) -> StringName:
	return d.identity.id if d.identity != null and not d.identity.id.is_empty() else d.id


## Every status a return hauls: the roster's `debuff`-tagged defs, in roster order.
static func hauled() -> Array[StatusDef]:
	var out: Array[StatusDef] = []
	for d in StatusRoster.shared().statuses:
		if d != null and d.tags.has(&"debuff"):
			out.append(d)
	return out


func _record(walk: RetractFront.Walk, lctx: LandingContext) -> void:
	if walk == null:
		return
	var from: Array = []
	for inc in lctx.incidents:
		from.append(inc.predecessor)
	walk.record(lctx.node, from)


func _outbound() -> PropagationSpread:
	if outbound_spread == null:
		outbound_spread = FanAllSpread.new()
	return outbound_spread


func _as_out(pick: PropagationPick, child_depth: int) -> RetractFront.Pick:
	var p := RetractFront.Pick.at(pick.node, RetractFront.Phase.OUT, child_depth)
	p.share = pick.share
	p.stack_share = pick.stack_share
	p.arrival_bearing = pick.arrival_bearing
	p.terminal = pick.terminal
	return p


func _in_place(lctx: LandingContext, k: int) -> RetractFront.Pick:
	var phase := RetractFront.Phase.BACK if lctx.cast.wave_index + 1 == turn_wave(k) \
			else RetractFront.Phase.WAIT
	return RetractFront.Pick.at(lctx.node, phase, k)


func _returns(st: RetractFront.State, lctx: LandingContext) -> Array[PropagationPick]:
	var out: Array[PropagationPick] = []
	var parents := st.walk.parents_of(lctx.node) if st.walk != null else [] as Array[SkillNode]
	if parents.is_empty():
		return out
	var weights: Array = parents.map(func(p: SkillNode) -> int: return st.walk.trails_of(p))
	var picks: Array[RetractFront.Pick] = []
	for p in parents:
		picks.append(RetractFront.Pick.at(p, RetractFront.Phase.BACK, st.depth - 1))
	for d in hauled():
		var now := roundi(lctx.spot_stacks_of(lctx.node, d.id))
		var seen := int(st.seen.get(d, 0))
		var passing := clampi(now - maxi(0, seen - load_for(d, lctx.cast.load)), 0, now)
		var shares := Apportion.largest_remainder(passing, weights)
		for i in parents.size():
			if shares[i] > 0:
				picks[i].cargo.append(RetractFront.Piece.of(lctx.node, d, shares[i]))
	for p in picks:
		if not p.cargo.is_empty():
			out.append(p)
	return out
