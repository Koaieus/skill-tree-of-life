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
## The least a Burning node pays when a shape adds up with its disc and the
## combined disc reaches anyone ([method fire_shaped_in]): its solo spend is
## raised to this, the shortfall nodeless. 0 turns it off. Tentative knob
## (#1828). Editor feedback: the sandbox host's blast tab.
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


## Fire's add-up (ADR 0084 §3, §4): a shape of [param shape_power] (the
## caller's: a blade vertex's excess at fill, a cast's points × its per-point
## power) and this disc at [param node] go off as ONE disc of
## [method shape_disc_radius]. A Burning node ([method power_at] > 0) pays its
## solo cost, 1 per reached node inside its own [method radius_at] disc, raised
## to [member solo_cost_floor] (the shortfall nodeless) when the combined disc
## reaches anyone; its own damage reads its excess only. A node that is not
## Burning runs the shape alone: no spend, no power, no own damage. No shape
## and no excess is no go-off; a disc reaching nobody spends nothing. Whether a
## centre copy lands is the caller's. [method fire_in] is the unshaped disc.
func fire_shaped_in(world: CombatWorld, node: SkillNode, read: TerrainRead, shape_power: float) -> GoOffResult:
	var out := GoOffResult.new()
	out.share = share
	if node == null:
		return out
	var excess := power_at(node, read, world)
	if excess <= 0:
		if shape_power <= 0.0:
			return out
		out.reach = shape_disc_radius(shape_power, 0.0, node.radius)
		for n in _within(node, out.reach):
			out.reached.append(GoOffResult.Reach.new(n))
		return out
	out.power = excess
	out.reach = shape_disc_radius(shape_power, excess, node.radius)
	out.own_damage = damage_per_power * excess
	var solo := {}
	for n in _within(node, radius_at(node, excess)):
		solo[n] = true
	var spent := 0
	for n in _within(node, out.reach):
		out.reached.append(GoOffResult.Reach.new(n))
		if solo.has(n):
			out.cost[n] = 1
			spent += 1
	if not out.reached.is_empty():
		out.nodeless_cost = maxi(solo_cost_floor - spent, 0)
	return out


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


## The unshaped disc's radius (ADR 0084 §2): `A × (√power + B) × node_radius`,
## [method shape_disc_radius] with no shape. Pure. Its readers reach it through
## Fire's def (`bands[0].go_off`): Burning's disc here, Burning's light (#1805)
## and the Fire shape on a cast (#1812); none copies the formula. Power ≤ 0
## gives A × B × node_radius (a reader that gates on power does so itself).
func disc_radius(power: float, node_radius: float) -> float:
	return shape_disc_radius(0.0, power, node_radius)


## The one radius function (ADR 0084 §2, §3): `A × (√shape_power + √excess +
## B) × node_radius` over [member radius_a] and [member radius_b],
## [param node_radius] being the ORIGIN node's (the disc's own node; a cast's
## seed). Pure; each root reads its term floored at 0, so shape 0 is
## [method disc_radius] and excess 0 is the shape alone. A reader that gates on
## power does so itself.
func shape_disc_radius(shape_power: float, excess: float, node_radius: float) -> float:
	return radius_a * (sqrt(maxf(shape_power, 0.0)) + sqrt(maxf(excess, 0.0)) + radius_b) * node_radius


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

