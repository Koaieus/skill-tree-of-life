extends GutTest

## [DiscGoOff] called directly through [method GoOff.fire] on a bare instance
## (the base law: power = Heat's excess over T, reach = [method
## DiscGoOff.disc_radius] off the origin node's radius, 1 per other node
## reached), reach by power (a node at the radius is reached, one just past it
## is not, the centre never); then Burning's disc end to end through
## [HitGather]'s stage one: the whole hit lands a centre copy and its terrain
## rider once.
##
## A node is reached when its hitbox touches the disc ([EuclideanRangeFinder]:
## centre distance less the node's own radius), so a node "at the radius" sits
## its own radius past it. Positions are float32: the node at the radius sits
## [constant _EPS] inside it, the one past it [constant _PAST] outside.

const _EPS := 0.001
const _PAST := 0.5
## The powers (Heat over T) the reach table fires at.
const _POWERS := [1, 2, 3]
## Rows sit this far apart on y, so no disc reaches another row's nodes.
const _ROW_GAP := 5000.0
## Each centre's anchor sits this far west of it: outside any disc.
const _FAR := 20000.0
const _RAW := 4.0

var _w: TestWorld


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	await get_tree().process_frame


func after_each() -> void:
	CombatWorld.reset_live()


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


func _read(node: SkillNode) -> TerrainRead:
	return TerrainRead.of(node.get_combat(), node)


func _reached(result: GoOffResult) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for r in result.reached:
		out.append(r.node)
	return out


## A node at [param pos] linked to its own far anchor (degree 1, so T > 0).
func _anchored(id: StringName, pos: Vector2) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = pos
	var anchor := _w.add_node(StringName("%s_anchor" % id))
	anchor.global_position = pos - Vector2(_FAR, 0.0)
	_w.link(n, anchor)
	return n


## A node whose hitbox sits [param edge] px from [param centre]'s centre, due east.
func _east_of(centre: SkillNode, id: StringName, edge: float) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = centre.global_position + Vector2(edge + n.radius, 0.0)
	return n


## [param n]'s Heat set to its T + [param excess].
func _prime(n: SkillNode, excess: int) -> void:
	var c := n.get_combat()
	c.add_terrain(_fire(), c.terrain_threshold() + excess - c.terrain_t())


# --- reach by power: the base law -----------------------------------------------

func test_the_disc_spends_one_per_node_reached_and_reaches_by_disc_radius() -> void:
	var disc := DiscGoOff.new()
	var red := _w.add_entity("Red")
	var rows: Array = []
	for i in _POWERS.size():
		var power: int = _POWERS[i]
		var centre := _anchored(StringName("C%d" % i), Vector2(0.0, _ROW_GAP * i))
		var reach := disc.disc_radius(power, centre.radius)
		var at := _east_of(centre, StringName("At%d" % i), reach - _EPS)
		var past := _east_of(centre, StringName("Past%d" % i), reach + _PAST)
		_w.allocate(red, [centre])
		rows.append([power, centre, at, past])
	await get_tree().process_frame
	for r: Array in rows:
		_prime(r[1], r[0])
	for r: Array in rows:
		var power: int = r[0]
		var centre: SkillNode = r[1]
		var result := disc.fire(centre, _read(centre))
		var reached := _reached(result)
		assert_eq(disc.power_at(centre, _read(centre)), power, "power is Heat's excess (%d)" % power)
		assert_eq(result.spend(), reached.size(), "1 per node reached at power %d" % power)
		assert_eq(result.nodeless_cost, 0, "nothing nodeless at power %d" % power)
		assert_almost_eq(result.share, disc.share, 0.0001, "the copies ride the disc's share")
		assert_false(reached.has(centre), "never the centre, power %d" % power)
		assert_almost_eq(disc.radius_at(centre, power), disc.disc_radius(power, centre.radius), 0.0001,
				"the disc's radius is disc_radius's at power %d" % power)
		assert_true(reached.has(r[2]), "the node at the radius is reached at power %d" % power)
		assert_false(reached.has(r[3]), "the node just past it is not, at power %d" % power)


func test_heat_at_t_is_no_go_off() -> void:
	var centre := _anchored(&"C", Vector2.ZERO)
	_east_of(centre, &"M", 1.0)
	_w.allocate(_w.add_entity("Red"), [centre])
	await get_tree().process_frame
	_prime(centre, 0)
	var result := DiscGoOff.new().fire(centre, _read(centre))
	assert_eq(result.power, 0, "no excess, no power")
	assert_true(result.reached.is_empty(), "power 0 is no go-off")
	assert_eq(result.spend(), 0, "and no spend")


# --- end to end: Burning's whole hit through the gather -------------------------
## An arrow-shaped hit (a damage head, 3 Poison, 1 Heat) tips a node at
## T to T + 1, one hostile inside the disc. The knobs are read from Fire's
## instance, never literals.

func _arrow_on(at: SkillNode, by: Entity, heat := 0) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var poison := StatusInstance.new()
	poison.def = preload("res://effects/status/poison.tres")
	poison.power = 3.0
	poison.raw = true
	var span: Array[HitInstance] = [d, poison]
	if heat > 0:
		var h := StatusInstance.new()
		h.def = _fire().terrain
		h.power = float(heat)
		h.raw = true
		span.append(h)
	for hit in span:
		hit.target = at
		hit.attacker = by
		hit.schedule_index = 0
	return span


func _at(copies: Array, n: SkillNode) -> Array:
	return copies.filter(func(h: HitInstance) -> bool: return h.target == n)


func _poison_of(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is StatusInstance and h.def.id == &"poison") \
			.map(func(h: HitInstance) -> float: return h.power)


func _damage_of(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is DamageInstance) \
			.map(func(h: HitInstance) -> float: return h.amount)


func test_burnings_whole_hit_lands_a_centre_copy_and_the_terrain_rider_once() -> void:
	var disc := _fire().bands[0].go_off as DiscGoOff
	assert_not_null(disc, "Fire's Burning band holds a DiscGoOff")
	if disc == null:
		return
	assert_true(disc.lands_on_own_node, "Burning lands a centre copy (ADR 0086 §1)")
	var struck := _anchored(&"Struck", Vector2.ZERO)
	var red := _w.add_entity("Red")
	var blue := _w.add_entity("Blue")
	var other := _east_of(struck, &"Other", disc.disc_radius(1, struck.radius) * 0.5)
	_w.link(struck, other)
	_w.allocate(red, [struck, other])
	await get_tree().process_frame
	_prime(struck, 0)
	assert_lt(1, other.get_combat().terrain_threshold() + 1, "fixture: Other stays unprimed after its copy")
	var span := _arrow_on(struck, blue, 1)
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	var copies := all.slice(span.size())
	var each := _RAW * disc.share + disc.damage_per_power * 1
	var own := _at(copies, struck)
	assert_true(_damage_of(own).has(each), "the struck node takes its centre landing at raw × share + own damage")
	assert_true(_poison_of(own).has(ceilf(3.0 * disc.share)), "with its Poison")
	var on_other := _at(copies, other)
	assert_eq(_damage_of(on_other), [each], "the disc node takes one copy")
	assert_eq(_poison_of(on_other), [ceilf(3.0 * disc.share)], "with 3 Poison × share")
	for c: HitInstance in own + on_other:
		assert_not_null(c.blast_mark, "every copy carries the go-off's mark")
	assert_true(copies.all(func(h: HitInstance) -> bool: return not (h is StatusInstance and h.def == _fire().terrain)),
			"no copy carries the terrain rider")
