@tool
class_name DiscGoOff
extends GoOff

## A disc [GoOff]: a node that goes off reaches every node inside one radius of
## it, the centre excluded, by shape alone, allocated or not (ADR 0084 §7); the
## hit's own target mask then decides which of them a copy lands on (the
## gather's, never the disc's). Its copies ride [member GoOff.share]; it deals
## no damage of its own.
##
## Power and radius each come through ONE read, picked by an export
## ([member power_source], [member radius_source]): the class is reused with
## other sources (#1800's Heat excess and ADR 0084 §2's radius), never
## subclassed for them. Go-off zero (#1799) is today's explosive detonation
## ported onto the gather: power is [method power_of] over the node's stored
## Explosive charges and the head's load, the radius
## [method ExplosiveSpread.radius_for], and the spend [method spend_of] —
## committed whatever the disc reaches, a lone charged node included, so it
## rides [member GoOffResult.nodeless_cost] and no reached node costs anything
## (Carried, tentative, not the owner's; #1799 NOTES). Power 0 is no go-off.

## Where the disc's power comes from. [code]EXPLOSIVE_CHARGES[/code] is go-off
## zero's: [method power_of] over the stored Explosive charges and the head's
## load, the terrain read ignored.
enum Power { EXPLOSIVE_CHARGES, HEAT_EXCESS }
## Where the disc's radius comes from. [code]EXPLOSIVE_SPREAD[/code] is go-off
## zero's: [method ExplosiveSpread.radius_for] (node radius × 3 × √power).
enum Radius { EXPLOSIVE_SPREAD, DISC }
## What the disc spends going off.
enum Spend { SPEND_OF, PER_NODE }

## The disc's power source (see [enum Power]).
@export var power_source: Power = Power.EXPLOSIVE_CHARGES
## The disc's radius source (see [enum Radius]).
@export var radius_source: Radius = Radius.EXPLOSIVE_SPREAD
## The disc's spend (see [enum Spend]).
@export var spend_source: Spend = Spend.SPEND_OF
## [method disc_radius]'s A.
@export_range(0.1, 5.0, 0.05) var radius_a := 2.0
## [method disc_radius]'s B.
@export_range(0.1, 5.0, 0.05) var radius_b := 1.0
## The disc's own damage per power.
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
	out.nodeless_cost = spend_at(node, read, hit_load, world)
	for n in _within(node, out.reach):
		out.reached.append(GoOffResult.Reach.new(n))
	return out


## The disc's power at [param node]: its one power read, through
## [member power_source], off [param world]'s store (live when null).
func power_at(node: SkillNode, _read: TerrainRead, hit_load: int, world: CombatWorld = null) -> int:
	match power_source:
		Power.EXPLOSIVE_CHARGES:
			var spread := _spread()
			if spread == null:
				return 0
			return power_of(maxi(hit_load, 0), _charges_at(node, world), spread.resonance)
	return 0


## What the disc spends going off at [param node], through
## [member power_source]: go-off zero's [method spend_of] off the stored
## charges of [param world] (live when null; [method present_on] names the
## holder it comes off, and [HitGather] commits it there).
func spend_at(node: SkillNode, _read: TerrainRead, hit_load: int, world: CombatWorld = null) -> int:
	match power_source:
		Power.EXPLOSIVE_CHARGES:
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
	return 0.0


## STUB (#1800 U3, red): the disc's radius for [param power] off an origin node
## of [param node_radius].
func disc_radius(_power: float, _node_radius: float) -> float:
	return 0.0


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
