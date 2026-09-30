class_name GateFlipInstance
extends HitInstance

## A melee fuse's timed gate flip (#1209): every gate in [member gates] flips
## at once at [member structural_key], then connectivity is judged ONCE, so two
## gates fused at the same t are order-independent. No HP — [member amount]
## stays 0. The stranded set rides [member HitInstance.deallocations], the
## repo's recorded-cascade shape: the authority stamps it on its shadow, a peer
## (and the authority's own replay) applies exactly that set.
##
## Landed through [method land_flip], never [method land_on]: the live half
## needs an [AllocationSystem] a [NodeCombat] cannot supply, so
## [method OutcomeApplier.land_one] dispatches here before its slice lookup.
##   * Shadow — no [Graph] to flip. The attacker's shadow mirror answers the
##     stranded set through the same [method GraphMirror.nodes_islanded_by_flipping]
##     [method AllocationSystem.gate_flip_cascade] calls (so the plan-time warning
##     is exact), keeps the flip so later samples cascade on the new topology,
##     and the set is cascaded on the shadow slices.
##   * Live — [method AllocationSystem.apply_gate_flip_recorded], the one flip
##     path [ToggleGatesCommand] uses, with the recorded set.
## [member target] is the first gate's `from` — identity for the schedule and
## the applier's null guard, nothing is landed on it.

## Resolve-local / rebuilt from ids; never on the wire as references.
var gates: Array[Gate] = []


func _init() -> void:
	kind = Kind.GATE_FLIP


## Never reached through the applier (see the class note); a direct caller
## gets the shadow half or a warning, never a half-applied live flip.
func land_on(_node: NodeCombat, world: CombatWorld) -> void:
	land_flip(world, null)


func land_flip(world: CombatWorld, alloc: AllocationSystem) -> void:
	effective_amount = 0.0
	if world.is_shadow():
		_land_shadow(world)
		return
	if alloc == null:
		push_warning("GateFlipInstance: a live flip needs an AllocationSystem; skipped")
		return
	var stranded: Array[SkillNode] = []
	for e in deallocations:
		if e.node != null:
			stranded.append(e.node)
	alloc.apply_gate_flip_recorded(gates, attacker, stranded)


func _land_shadow(world: CombatWorld) -> void:
	deallocations = []
	if attacker == null:
		return
	var ec := world.combat_for_entity(attacker)
	if ec == null:
		return
	var mirror := ec.mirror()
	var core := ec.core()
	if mirror == null or core == null or core.real() == null:
		return
	var stranded := mirror.nodes_islanded_by_flipping(gates, core.real())
	# Keep the flip on the shadow's own topology: a later landing's cascade (or
	# a later fuse) must read the post-flip board. An unmirrored endpoint is
	# not this entity's and strands nothing, exactly as live.
	for g in gates:
		if g == null:
			continue
		var a := mirror.vertex_id(g.from)
		var b := mirror.vertex_id(g.to)
		if a < 0 or b < 0 or a == b:
			continue
		if mirror.astar.are_points_connected(a, b):
			mirror.astar.disconnect_points(a, b)
		else:
			mirror.astar.connect_points(a, b)
	var combats: Array[NodeCombat] = []
	for n in stranded:
		var slice := world.combat_for(n)
		if slice != null and slice.owner() == ec and slice != core:
			combats.append(slice)
	deallocations = ec.apply_cascade(combats, null, true)


func _to_string() -> String:
	return "GateFlipInstance(%d gate(s) @ %.3f, %d stranded)" % [
		gates.size(), structural_key, deallocations.size()]
