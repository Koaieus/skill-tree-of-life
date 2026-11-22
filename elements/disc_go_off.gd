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
## base [GoOff] rule: [member GoOff.void_floor] nodeless plus 1 per other node
## reached ([member GoOffResult.cost]), each of those +1 Heat on the node it
## reached on the [member spent_heat_goes_to] default. A disc reaching none
## makes no entry and still voids its floor ([member GoOff.floor_when_unreached]).
## The own damage is
## [member damage_per_power]: the class is reused with other values, never
## subclassed for them. Burning's (`elements/defs/fire.tres`, on Fire's
## Burning band) sets [member damage_per_power] 2. Power 0 is no go-off.

## Where the disc's power comes from. [code]HEAT_EXCESS[/code] is Burning's:
## the read's Heat over its T ([method Terrain.excess]), read after the hit's
## riders landed, the overflow past the cap included.
enum Power { HEAT_EXCESS }

enum SpentHeatGoesTo { REACHED_NODE, VOID }

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
## Where each per-reached Heat stack goes: +1 Heat on the node it reached (a
## blast is hot, ADR 0097 §3) or nowhere. Mirrors
## [member EdgeGoOff.spent_charge_goes_to]. Tentative knob.
@export_enum("Reached node", "Void") var spent_heat_goes_to: int = SpentHeatGoesTo.REACHED_NODE

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
		_pay_for(out, n)
	out.nodeless_cost = floor_for(not out.reached.is_empty())
	return out


func fire_with(world: CombatWorld, node: SkillNode, read: TerrainRead, source: GoOffSource) -> GoOffResult:
	if source == null:
		return fire_in(world, node, read)
	return fire_shaped_in(world, node, read, source)


## [param n]'s per-reached part on [param out]: 1 stack, and its +1 Heat on
## the [member spent_heat_goes_to] default.
func _pay_for(out: GoOffResult, n: SkillNode) -> void:
	out.cost[n] = 1
	if spent_heat_goes_to == SpentHeatGoesTo.REACHED_NODE:
		out.effect[n] = 1


## The incoming party's power: a copy's excess over its threshold
## ([method power_at] its read), a shape's points × its element's per-point
## power ([method Element.shape_power]); 0 for none.
func power_from(source: GoOffSource) -> float:
	if source == null:
		return 0.0
	if source.read != null:
		return float(power_at(null, source.read))
	return source.element.shape_power(source.points) if source.is_shape() else 0.0


## Fire's add-up (ADR 0084 §3, §4; ADR 0098): the node's disc and the incoming
## [param source] (a blade copy's excess, a cast's shape: [method power_from])
## go off as ONE disc of [method shape_disc_radius] over both powers. Each
## primed party pays its solo cost: [member GoOff.void_floor] plus 1 per
## reached node inside its own [method radius_at] disc around [param node]
## (the node's [member GoOffResult.cost] + nodeless; a copy with a payer its
## [member GoOffResult.incoming_cost]); a shape pays nothing. While a party is
## primed every node the combined disc reaches takes +1 Heat on the default.
## Own damage reads the node's excess only. [param read] null is an unprimed
## node; nothing on either side is no go-off. Whether a centre copy lands is
## the caller's. [method fire_in] is the unshaped disc.
func fire_shaped_in(world: CombatWorld, node: SkillNode, read: TerrainRead, source: GoOffSource) -> GoOffResult:
	var out := GoOffResult.new()
	out.share = share
	if node == null:
		return out
	var excess := power_at(node, read, world)
	var incoming := power_from(source)
	if excess <= 0 and incoming <= 0.0:
		return out
	var copy_primed := incoming > 0.0 and source.read != null
	var copy_pays := copy_primed and source.pays()
	var lands := (excess > 0 or copy_primed) and spent_heat_goes_to == SpentHeatGoesTo.REACHED_NODE
	out.power = maxi(excess, 0)
	out.reach = shape_disc_radius(incoming, excess, node.radius)
	out.own_damage = damage_per_power * maxi(excess, 0)
	var own := _set_of(_within(node, radius_at(node, excess))) if excess > 0 else {}
	var theirs := _set_of(_within(node, radius_at(node, int(incoming)))) if copy_pays else {}
	for n in _within(node, out.reach):
		out.reached.append(GoOffResult.Reach.new(n))
		if own.has(n):
			out.cost[n] = 1
		if theirs.has(n):
			out.incoming_at[n] = 1
		if lands:
			out.effect[n] = 1
	if excess > 0:
		out.nodeless_cost = floor_for(not out.reached.is_empty())
	if copy_pays:
		out.incoming_cost = floor_for(not out.reached.is_empty()) + out.incoming_at.size()
	return out


static func _set_of(nodes: Array[SkillNode]) -> Dictionary:
	var out := {}
	for n in nodes:
		out[n] = true
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

