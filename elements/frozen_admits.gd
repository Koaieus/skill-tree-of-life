@tool
class_name FrozenAdmits
extends Admits

## Ice's answers on a Frozen node, one resource set on both Ice bands (Frozen
## and Deep freeze), so a deep-frozen node answers exactly as a Frozen one.
## Ice owns no gather code and no terrain write: [HitGather] asks, settles the
## answer and commits it. See `docs/domain/elements.md` § Ice.
##
## An arrival breaks the ice alone ([method breaks]): its crit, or, on a node
## with a holder, its damage as the floater shows it ([method mitigated]) at or
## above [member break_fraction_max_hp] × the holder's max HP. The admit
## absorbs a copy that does not break it; the read after the riders shatters
## the node on any breaker, else ends every path through it. Knobs tentative.

## The flat breaker, a fraction of the holder's max HP. No holder, no flat
## breaker: only a crit (or a blade's touch) breaks an unallocated node.
@export_range(0.0, 1.0, 0.01) var break_fraction_max_hp: float = 0.10
## Extra landings of its own payload each breaking arrival takes (a break
## counts as this many channels).
@export_range(0, 4, 1, "or_greater") var break_channels: int = 2
## Burst HP per excess stack, × the holder's max HP.
@export_range(0.0, 0.2, 0.001, "or_greater") var shatter_fraction_per_stack: float = 0.01
## Share of the excess (count − T) a shatter spends, rounded to whole stacks.
@export_range(0.0, 1.0, 0.05) var shatter_spend_fraction: float = 1.0
## A Frozen blade vertex's damage multiplier per copied excess stack, no base
## term. Read at blade fill, not by either answer here.
@export_range(0.0, 1.0, 0.01, "or_greater") var vertex_bonus_per_excess: float = 0.10


## A copy lands only if it breaks the ice; a head, and a centre copy, always.
func admit_in(world: CombatWorld, node: SkillNode, _before: TerrainRead, arrival: Arrival) -> bool:
	if not arrival.is_copy or arrival.centre:
		return true
	return breaks(world, node, arrival)


## Once per generation, after the riders (the band is Frozen or Deep freeze, or
## this is not asked): each arrival tested alone; any breaker shatters the
## node, else paths end here.
func read_in(world: CombatWorld, node: SkillNode, after: TerrainRead,
		arrivals: Array[Arrival]) -> AdmitsAnswer:
	var answer := AdmitsAnswer.new()
	answer.extra_landings = break_channels
	for i in arrivals.size():
		var a := arrivals[i]
		if not a.centre and breaks(world, node, a):
			answer.breakers.append(i)
	_snap_blades(arrivals)
	if answer.breakers.is_empty():
		answer.paths_end = true
		return answer
	var ice := ElementRoster.shared().by_id(&"ice")
	var excess := Terrain.excess(after.count(ice), after.threshold) if ice != null else 0
	answer.spend = roundi(excess * shatter_spend_fraction)
	var holder := _holder(world, node)
	if holder != null:
		answer.burst = (float(excess) + added_excess(world, node, arrivals)) \
				* shatter_fraction_per_stack * holder.get_max_hp()
	answer.hp = answer.burst
	return answer


## Whether [param arrival] breaks the ice on its own: a crit, a blade vertex's
## touch at least as heavy as the node ([method BladeDamageInstance.touch_weight]
## ≥ the node's [method BladeDamageInstance.weight_of]; the direct contact
## only, never its copies), or (with a holder) its mitigated damage at or above
## the flat breaker.
func breaks(world: CombatWorld, node: SkillNode, arrival: Arrival) -> bool:
	if arrival.head != null and arrival.head.is_crit:
		return true
	if not arrival.is_copy and arrival.head is BladeDamageInstance:
		var touch := (arrival.head as BladeDamageInstance).touch_weight()
		if touch >= 0.0 and node != null and touch >= BladeDamageInstance.weight_of(node.radius):
			return true
	var holder := _holder(world, node)
	if holder == null:
		return false
	return mitigated(world, node, arrival) >= break_fraction_max_hp * holder.get_max_hp()


## [member Arrival.amount] as the floater will show it, as
## [method NodeCombat.take_damage] lands it: made whole ([method HitPoints.whole]),
## then [method Mitigation.compute] with the node's armor and
## `min_damage_taken` and the head's pierce; TRUE skips the mitigation.
static func mitigated(world: CombatWorld, node: SkillNode, arrival: Arrival) -> float:
	var amount := HitPoints.whole(arrival.amount)
	var head := arrival.head as DamageInstance
	if head != null and head.type == DamageInstance.Type.TRUE:
		return amount
	var slice := world.combat_for(node) as NodeCombat if world != null else null
	var armor := 0.0
	var floor_min := 0.0
	if slice != null:
		armor = float(slice.get_local_value(&"armor"))
		floor_min = float(slice.get_local_value(&"min_damage_taken"))
	return Mitigation.compute(amount, armor, floor_min,
			head.armor_pierce if head != null else null)


## Excess added to the burst's input, never to the spend: the seat a cast's
## concentrate fills (hops removed × its knob). Base: none.
func added_excess(_world: CombatWorld, _node: SkillNode, _arrivals: Array[Arrival]) -> float:
	return 0.0


static func _holder(world: CombatWorld, node: SkillNode) -> EntityCombat:
	var slice := world.combat_for(node) as NodeCombat if world != null else null
	return slice.owner() if slice != null else null


## Every blade contact read here met a node still Frozen after its riders
## (this read is asked only then): its vertex pops, after the breakers are
## read, whether it broke the ice or not. A contact whose riders thawed the
## node is never read here, so its vertex lives on.
static func _snap_blades(arrivals: Array[Arrival]) -> void:
	for a in arrivals:
		if not a.is_copy and a.head is BladeDamageInstance:
			(a.head as BladeDamageInstance).snap_on_ice()
