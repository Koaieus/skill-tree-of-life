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
## Power comes through ONE read, picked by [member power_source]; the radius
## is [method disc_radius] off the origin node's own radius; the spend is the
## base [GoOff] law, 1 per other node reached ([member GoOffResult.cost]), so
## a disc reaching none spends 0 and does not go off. The own damage is
## [member damage_per_power]: the class is reused with other values, never
## subclassed for them. Burning's (`elements/defs/fire.tres`, on Fire's
## Burning band) sets [member damage_per_power] 2. Power 0 is no go-off.

## Where the disc's power comes from. [code]HEAT_EXCESS[/code] is Burning's:
## the read's Heat over its T ([method Terrain.excess]), read after the hit's
## riders landed, the overflow past the cap included.
enum Power { HEAT_EXCESS }

## The disc's power source (see [enum Power]).
@export var power_source: Power = Power.HEAT_EXCESS
## [method disc_radius]'s A, the scale (ADR 0084 §2). Tentative knob (#1800).
## Editor feedback: the sandbox host's blast tab.
@export_range(0.1, 5.0, 0.05) var radius_a := 2.0
## [method disc_radius]'s B, the floor under √power, so a power-1 disc already
## clears its neighbours (ADR 0084 §2). Tentative knob (#1800).
@export_range(0.1, 5.0, 0.05) var radius_b := 1.0
## The own damage per power the disc adds to each of its entries (the "little
## damage ∝ power"). 0 by default; Burning's 2 on Fire's instance.
## Tentative knob (#1800).
@export_range(0.0, 10.0, 0.1) var damage_per_power := 0.0
## STUB
@export_range(0, 3) var solo_cost_floor := 1

## Answers geometry only, at whatever reach it is asked ([method _within]).
var _finder: EuclideanRangeFinder = null


## The disc on the live world ([method fire_in] with none).
func fire(node: SkillNode, read: TerrainRead) -> GoOffResult:
	return fire_in(null, node, read)


## The disc going off at [param node] off [param read] (the gather's, after
## the generation's riders landed): its spend, its reach, and the
## [BlastMark]'s reach and power ([member GoOffResult.reach],
## [member GoOffResult.power]). [param world] is the [GoOff] contract's; the
## disc does not read it.
func fire_in(world: CombatWorld, node: SkillNode, read: TerrainRead) -> GoOffResult:
	var out := GoOffResult.new()
	out.share = share
	if node == null:
		return out
	var power := power_at(node, read, world)
	if power <= 0:
		return out
	out.power = power
	out.reach = radius_at(node, power)
	out.own_damage = damage_per_power * power
	for n in _within(node, out.reach):
		out.reached.append(GoOffResult.Reach.new(n))
		out.cost[n] = 1
	return out


## STUB
func fire_shaped_in(_world: CombatWorld, _node: SkillNode, _read: TerrainRead, _shape_power: float) -> GoOffResult:
	return GoOffResult.new()


## The disc's power at [param node]: its one power read, through
## [member power_source], off [param read] (the gather's, after the
## generation's riders landed).
func power_at(_node: SkillNode, read: TerrainRead, _world: CombatWorld = null) -> int:
	match power_source:
		Power.HEAT_EXCESS:
			return Terrain.excess(maxi(read.t, 0), read.threshold) if read != null else 0
	return 0


## The disc's radius in px at [param node] for [param power] (the mark's
## reach): [method disc_radius] off the node's own radius.
func radius_at(node: SkillNode, power: int) -> float:
	if node == null:
		return 0.0
	return disc_radius(power, node.radius)


## The one radius function (ADR 0084 §2): `A × (√power + B) × node_radius`
## over [member radius_a] and [member radius_b], [param node_radius] being the
## ORIGIN node's (the disc's own node; a cast's seed). Pure. Its readers reach
## it through Fire's def (`bands[0].go_off`): Burning's disc here, Burning's
## light (#1805) and the Fire shape on a cast (#1812); none copies the formula.
## Power ≤ 0 gives A × B × node_radius (a reader that gates on power does so
## itself).
func disc_radius(power: float, node_radius: float) -> float:
	return radius_a * (sqrt(maxf(power, 0.0)) + radius_b) * node_radius


## STUB
func shape_disc_radius(_shape_power: float, _excess: float, _node_radius: float) -> float:
	return 0.0


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

