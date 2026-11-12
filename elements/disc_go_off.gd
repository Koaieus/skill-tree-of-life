@tool
class_name DiscGoOff
extends GoOff

## A disc [GoOff]: a node that goes off reaches every node inside one radius of
## it, the centre excluded, by shape alone, allocated or not (ADR 0084 §7); the
## hit's own target mask then decides which of them a copy lands on (the
## gather's, never the disc's). Its copies ride [member GoOff.share], each
## (the centre landing included) plus the own damage
## `damage_per_power × power` (ADR 0086 §2).
##
## Power, radius and spend each come through ONE read, picked by an export
## ([member power_source], [member radius_source], [member spend_source]), and
## the own damage is [member damage_per_power]: the class is reused with other
## values, never subclassed for them. Every class default is go-off zero's
## value. Go-off zero (#1799) is today's explosive detonation
## ported onto the gather: power is [method power_of] over the node's stored
## Explosive charges and the head's load, the radius
## [method ExplosiveSpread.radius_for], and the spend [method spend_of] —
## committed whatever the disc reaches, a lone charged node included, so it
## rides [member GoOffResult.nodeless_cost] and no reached node costs anything
## (Carried, tentative, not the owner's; #1799 NOTES); no own damage.
## Burning's (#1800, `elements/defs/fire.tres`, on Fire's Burning band) is
## Heat's excess over T, [method disc_radius], 1 Heat per other node reached
## (none reached: spend 0 and no go-off, the base [GoOff] law) and
## [member damage_per_power] 2. Power 0 is no go-off.

## Where the disc's power comes from. [code]EXPLOSIVE_CHARGES[/code] is go-off
## zero's: [method power_of] over the stored Explosive charges and the head's
## load, the terrain read ignored. [code]HEAT_EXCESS[/code] is Burning's: the
## read's Heat over its T ([method Terrain.excess]), read after the hit's
## riders landed, the overflow past the cap included.
enum Power { EXPLOSIVE_CHARGES, HEAT_EXCESS }
## Where the disc's radius comes from. [code]EXPLOSIVE_SPREAD[/code] is go-off
## zero's: [method ExplosiveSpread.radius_for] (node radius × 3 × √power).
## [code]DISC[/code] is Burning's: [method disc_radius] off the node's own radius.
enum Radius { EXPLOSIVE_SPREAD, DISC }
## What the disc spends going off. [code]SPEND_OF[/code] is go-off zero's:
## [method spend_of], nodeless, whatever the disc reaches.
## [code]PER_NODE[/code] is the base [GoOff] law, Burning's: 1 per other node
## reached ([member GoOffResult.cost]), so a disc reaching none spends 0.
enum Spend { SPEND_OF, PER_NODE }

## The disc's power source (see [enum Power]).
@export var power_source: Power = Power.EXPLOSIVE_CHARGES
## The disc's radius source (see [enum Radius]).
@export var radius_source: Radius = Radius.EXPLOSIVE_SPREAD
## The disc's spend (see [enum Spend]).
@export var spend_source: Spend = Spend.SPEND_OF
## [method disc_radius]'s A, the scale (ADR 0084 §2). Tentative knob (#1800).
## Editor feedback: the sandbox host's blast tab.
@export_range(0.1, 5.0, 0.05) var radius_a := 2.0
## [method disc_radius]'s B, the floor under √power, so a power-1 disc already
## clears its neighbours (ADR 0084 §2). Tentative knob (#1800).
@export_range(0.1, 5.0, 0.05) var radius_b := 1.0
## The own damage per power the disc adds to each of its entries (the "little
## damage ∝ power"). Go-off zero's 0; Burning's 2 on Fire's instance.
## Tentative knob (#1800).
@export_range(0.0, 10.0, 0.1) var damage_per_power := 0.0

const EXPLOSIVE := &"explosive"

## Answers geometry only, at whatever reach it is asked ([method _within]).
var _finder: EuclideanRangeFinder = null


## The disc on the live world ([method fire_in] with none).
func fire(node: SkillNode, read: TerrainRead, hit_load: int) -> GoOffResult:
	return fire_in(null, node, read, hit_load)


## The disc going off at [param node], reading the store of [param world] (the
## gather's; live when null): its spend, its reach, and the [BlastMark]'s
## reach and power ([member GoOffResult.reach], [member GoOffResult.power]).
func fire_in(world: CombatWorld, node: SkillNode, read: TerrainRead, hit_load: int) -> GoOffResult:
	var out := GoOffResult.new()
	out.share = share
	if node == null:
		return out
	var power := power_at(node, read, hit_load, world)
	if power <= 0:
		return out
	out.power = power
	out.reach = radius_at(node, power)
	out.own_damage = damage_per_power * power
	out.nodeless_cost = spend_at(node, read, hit_load, world)
	for n in _within(node, out.reach):
		out.reached.append(GoOffResult.Reach.new(n))
		if spend_source == Spend.PER_NODE:
			out.cost[n] = 1
	return out


## The disc's power at [param node]: its one power read, through
## [member power_source], off [param world]'s store (live when null) or
## [param read] (the gather's, after the generation's riders landed).
func power_at(node: SkillNode, read: TerrainRead, hit_load: int, world: CombatWorld = null) -> int:
	match power_source:
		Power.EXPLOSIVE_CHARGES:
			var spread := _spread()
			if spread == null:
				return 0
			return power_of(maxi(hit_load, 0), _charges_at(node, world), spread.resonance)
		Power.HEAT_EXCESS:
			return Terrain.excess(maxi(read.t, 0), read.threshold) if read != null else 0
	return 0


## The disc's nodeless spend at [param node], through [member spend_source]:
## go-off zero's [method spend_of] off the stored charges of [param world]
## (live when null; [method present_on] names the holder it comes off, and
## [HitGather] commits it there). [code]PER_NODE[/code] has none: its spend
## is the reached nodes' cost ([method fire_in]).
func spend_at(node: SkillNode, _read: TerrainRead, hit_load: int, world: CombatWorld = null) -> int:
	match spend_source:
		Spend.SPEND_OF:
			return spend_of(maxi(hit_load, 0), _charges_at(node, world))
	return 0


## The disc's radius in px at [param node] for [param power]: its one radius
## read, through [member radius_source] (the mark's reach).
func radius_at(node: SkillNode, power: int) -> float:
	if node == null:
		return 0.0
	match radius_source:
		Radius.EXPLOSIVE_SPREAD:
			var spread := _spread()
			return spread.radius_for(node.radius, power) if spread != null else 0.0
		Radius.DISC:
			return disc_radius(power, node.radius)
	return 0.0


## The one radius function (ADR 0084 §2): `A × (√power + B) × node_radius`
## over [member radius_a] and [member radius_b], [param node_radius] being the
## ORIGIN node's (the disc's own node; a cast's seed). Pure. Its readers reach
## it through Fire's def (`bands[0].go_off`): Burning's disc here, Burning's
## light (#1805) and the Fire shape on a cast (#1812); none copies the formula.
## Power ≤ 0 gives A × B × node_radius (a reader that gates on power does so
## itself).
func disc_radius(power: float, node_radius: float) -> float:
	return radius_a * (sqrt(maxf(power, 0.0)) + radius_b) * node_radius


## Charges a hit with [param load] spends off [param present]: none on a clean
## node, else `max(1, min(load, present))` — a spark always takes one.
static func spend_of(load: int, present: int) -> int:
	if present <= 0:
		return 0
	return maxi(1, mini(load, present))


## A detonation's power: `load + present + 2·r·min(load, present)`, the
## shared chunk weighted [param resonance] on each side. 0 = no blast.
static func power_of(load: int, present: int, resonance: int) -> int:
	var shared := mini(load, present)
	return maxi(load, 0) + maxi(present, 0) + 2 * resonance * maxi(shared, 0)


## `[holder, charges]`: the Explosive charges stored on [param slice] — or, on
## a core with none, its owner's entity-hosted ones. The holder is what a
## spend comes off ([NodeCombat] or [EntityCombat]).
static func present_on(slice: NodeCombat) -> Array:
	if slice == null:
		return [null, 0.0]
	var power := slice.get_status_power(EXPLOSIVE)
	if power <= 0.0 and slice.is_core() and slice.owner() != null:
		var core := slice.owner()
		return [core, core.get_status_power(EXPLOSIVE)]
	return [slice, power]


## The store go-off zero reads at [param node]: [param world]'s slice, the
## gather's (a spell resolves on a shadow); live when null.
func _store(node: SkillNode, world: CombatWorld = null) -> NodeCombat:
	if node == null:
		return null
	return (world if world != null else CombatWorld.live()).combat_for(node)


func _charges_at(node: SkillNode, world: CombatWorld = null) -> int:
	return maxi(int(present_on(_store(node, world))[1]), 0)


## Every node whose hitbox touches the disc of [param reach] around
## [param node], the centre excluded: shape alone, over the whole board (the
## graph's global [Navigator], as today's blast gathers).
func _within(node: SkillNode, reach: float) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	var graph := node.get_graph()
	if reach <= 0.0 or graph == null or graph.navigator == null:
		return out
	if _finder == null:
		_finder = EuclideanRangeFinder.new()
	for n: SkillNode in _finder.gather_reach(node, graph.navigator, reach):
		if n != node:
			out.append(n)
	return out


static func _spread() -> ExplosiveSpread:
	var roster := StatusRoster.shared()
	var def := roster.by_concept(EXPLOSIVE) if roster != null else null
	return def.spread as ExplosiveSpread if def != null else null
