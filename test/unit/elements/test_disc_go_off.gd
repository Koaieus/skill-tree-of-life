extends GutTest

## #1799 (Unit D): go-off zero's disc, [DiscGoOff], called directly through
## [method GoOff.fire]: the spend/power table (acceptance 1: `present` is the
## stored charges before the hit), reach by power at every power of that table
## (a node at the radius is reached, one just past it is not, the centre
## never), and the spend that commits whatever the disc reaches (Carried,
## NOTES). Unit F adds acceptance 3a's end-to-end fixture below.
##
## A node is reached when its hitbox touches the disc ([EuclideanRangeFinder]:
## centre distance less the node's own radius), so a node "at the radius" sits
## its own radius past it. Positions are float32: the node at the radius sits
## [constant _EPS] inside it, the one past it [constant _PAST] outside.

const _EPS := 0.001
const _PAST := 0.5
## `[load, present, spent, power]` at resonance 1 (acceptance 1's table).
const _TABLE := [[3, 0, 0, 3], [3, 5, 3, 14], [3, 1, 1, 6], [0, 5, 1, 5], [0, 0, 0, 0], [3, 2, 2, 9]]
## Rows sit this far apart on y, so no disc reaches another row's nodes. A
## centre is allocated: an unowned node hosts no Explosive charge.
const _ROW_GAP := 5000.0

var _w: TestWorld


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	await get_tree().process_frame


func _explosive() -> StatusDef:
	return StatusRoster.shared().by_concept(&"explosive")


func _spread() -> ExplosiveSpread:
	return _explosive().spread as ExplosiveSpread


func _charge(holder: Object, n: int) -> void:
	if n > 0:
		holder.get_combat().apply_status(_explosive(), float(n))


func _read(node: SkillNode) -> TerrainRead:
	return TerrainRead.of(node.get_combat(), node)


func _reached(result: GoOffResult) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for r in result.reached:
		out.append(r.node)
	return out


## A node whose hitbox sits [param edge] px from [param centre]'s centre, due east.
func _east_of(centre: SkillNode, id: StringName, edge: float) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = centre.global_position + Vector2(edge + n.radius, 0.0)
	return n


# --- spend and power: acceptance 1's table, on the disc ------------------------

func test_spend_and_power_follow_the_formula() -> void:
	for row in _TABLE:
		assert_eq(DiscGoOff.spend_of(row[0], row[1]), row[2], "spent for %s" % [row])
		assert_eq(DiscGoOff.power_of(row[0], row[1], 1), row[3], "power for %s" % [row])
	assert_eq(DiscGoOff.power_of(3, 2, 0), 5, "resonance 0: load + present")
	assert_eq(DiscGoOff.power_of(3, 2, 2), 13, "resonance weighs the shared chunk on each side")


# --- reach by power: every power of the table ----------------------------------

func test_the_disc_spends_and_reaches_by_power_at_every_power_of_the_table() -> void:
	var disc := DiscGoOff.new()
	var red := _w.add_entity("Red")
	var rows: Array = []
	for i in _TABLE.size():
		var row: Array = _TABLE[i]
		var centre := _w.add_node(StringName("C%d" % i))
		centre.global_position = Vector2(0.0, _ROW_GAP * i)
		_w.allocate(red, [centre])
		var reach := _spread().radius_for(centre.radius, maxi(row[3], 1))
		var at := _east_of(centre, StringName("At%d" % i), reach - _EPS)
		var past := _east_of(centre, StringName("Past%d" % i), reach + _PAST)
		rows.append([row, centre, at, past])
	await get_tree().process_frame
	for r: Array in rows:
		_charge(r[1], r[0][1])
	for r: Array in rows:
		var row: Array = r[0]
		var centre: SkillNode = r[1]
		var result := disc.fire(centre, _read(centre), row[0])
		var reached := _reached(result)
		assert_eq(disc.power_at(centre, _read(centre), row[0]), row[3], "power for %s" % [row])
		assert_eq(result.spend(), row[2], "the disc spends spend_of for %s" % [row])
		assert_true(result.cost.is_empty(), "no per-node cost: the spend is the node's own, %s" % [row])
		assert_false(reached.has(centre), "never the centre, %s" % [row])
		assert_almost_eq(result.share, disc.share, 0.0001, "the copies ride the disc's share")
		assert_eq(result.own_damage, 0.0, "the disc deals no damage of its own")
		if row[3] <= 0:
			assert_true(reached.is_empty(), "power 0 is no go-off: %s" % [row])
			continue
		assert_almost_eq(disc.radius_at(centre, row[3]), _spread().radius_for(centre.radius, row[3]), 0.0001,
				"the disc's radius is radius_for's at power %d" % row[3])
		assert_true(reached.has(r[2]), "the node at the radius is reached at power %d" % row[3])
		assert_false(reached.has(r[3]), "the node just past it is not, at power %d" % row[3])


func test_a_lone_charged_node_still_spends() -> void:
	var centre := _w.add_node(&"C", Vector2.ZERO)
	_w.allocate(_w.add_entity("Red"), [centre])
	await get_tree().process_frame
	_charge(centre, 2)
	var result := DiscGoOff.new().fire(centre, _read(centre), 0)
	assert_true(result.reached.is_empty(), "fixture: the disc reaches no other node")
	assert_eq(result.spend(), DiscGoOff.spend_of(0, 2), "go-off zero spends whatever its disc reaches")


func test_a_core_with_no_charges_reads_its_owners_entity_rows() -> void:
	var core := _w.add_node(&"Core", Vector2.ZERO)
	var red := _w.add_entity("Red")
	_w.allocate(red, [core])
	await get_tree().process_frame
	assert_true(core.get_combat().is_core(), "fixture: the node is red's core")
	_charge(red, 2)
	var disc := DiscGoOff.new()
	var held := DiscGoOff.present_on(core.get_combat())
	assert_same(held[0], red.get_combat(), "the holder is the owner's entity rows")
	assert_almost_eq(float(held[1]), 2.0, 0.0001, "the entity's charges are present")
	assert_eq(disc.power_at(core, _read(core), 3), DiscGoOff.power_of(3, 2, _spread().resonance),
			"power reads the entity's charges plus the head's load")
	assert_eq(disc.fire(core, _read(core), 3).spend(), DiscGoOff.spend_of(3, 2), "and spends off them")


# --- acceptance 3a: go-off zero and the whole hit, end to end (Unit F) ---------
## Through [HitGather]'s stage one, on a disc the test authors on the Explosive
## [Aspect] (F-c authors it on explosive.tres): an arrow-shaped hit (a load-0
## damage head, 3 Poison) on a 2-charge node with one hostile inside the disc.
## The knobs are read from the instance, never literals.

const _RAW := 4.0

var _aspect: Aspect = null
var _was: GoOff = null


func after_each() -> void:
	if _aspect != null:
		_aspect.go_off = _was
	_aspect = null
	CombatWorld.reset_live()


func _authored(share: float, own_node: bool) -> DiscGoOff:
	_aspect = AspectRoster.shared().by_id(&"explosive")
	_was = _aspect.go_off
	var disc := DiscGoOff.new()
	disc.share = share
	disc.lands_on_own_node = own_node
	_aspect.go_off = disc
	return disc


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
		h.def = ElementRoster.shared().by_id(&"fire").terrain
		h.power = float(heat)
		h.raw = true
		span.append(h)
	for hit in span:
		hit.target = at
		hit.attacker = by
		hit.schedule_index = 0
	return span


## `[struck, disc node, copies]` after stage one on the 3a fixture.
func _three_a(heat := 0) -> Array:
	var struck := _w.add_node(&"Struck", Vector2.ZERO)
	var red := _w.add_entity("Red")
	var blue := _w.add_entity("Blue")
	var other := _east_of(struck, &"Other", _spread().radius_for(struck.radius, 2) * 0.5)
	_w.allocate(red, [struck, other])
	await get_tree().process_frame
	_charge(struck, 2)
	var span := _arrow_on(struck, blue, heat)
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return [struck, other, all.slice(span.size())]


func _at(copies: Array, n: SkillNode) -> Array:
	return copies.filter(func(h: HitInstance) -> bool: return h.target == n)


func _poison_of(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is StatusInstance and h.def.id == &"poison") \
			.map(func(h: HitInstance) -> float: return h.power)


func _damage_of(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is DamageInstance) \
			.map(func(h: HitInstance) -> float: return h.amount)


func test_go_off_zero_lands_one_copy_per_disc_node_and_none_on_the_struck_node() -> void:
	var disc := _authored(0.5, false)
	var got: Array = await _three_a()
	var copies: Array = got[2]
	assert_true(_at(copies, got[0]).is_empty(), "the struck node takes the arrow alone: no copy, no mark")
	var other := _at(copies, got[1])
	assert_eq(_damage_of(other), [_RAW * disc.share], "the disc node's copy deals raw × share")
	assert_eq(_poison_of(other), [ceilf(3.0 * disc.share)], "and Poison ceil(3 × share)")
	for c: HitInstance in other:
		assert_not_null(c.blast_mark, "every copy carries the go-off's mark")


func test_the_whole_hit_alternative_lands_a_centre_copy_and_the_terrain_rider_once() -> void:
	var disc := _authored(1.0, true)
	var got: Array = await _three_a(1)
	var copies: Array = got[2]
	var struck: SkillNode = got[0]
	var own := _at(copies, struck)
	assert_eq(_damage_of(own), [_RAW * disc.share], "the struck node's centre copy at share × raw")
	assert_eq(_poison_of(own), [ceilf(3.0 * disc.share)], "with its Poison: two landings with the arrow's")
	var other := _at(copies, got[1])
	assert_eq(_damage_of(other), [_RAW * disc.share], "the disc node takes one copy")
	assert_eq(_poison_of(other), [ceilf(3.0 * disc.share)], "with 3 Poison")
	var fire := ElementRoster.shared().by_id(&"fire")
	assert_eq(CombatWorld.live().combat_for(struck).terrain_count(fire), 1, "the terrain rider lands once")
	assert_true(copies.all(func(h: HitInstance) -> bool: return not (h is StatusInstance and h.def == fire.terrain)),
			"no copy carries the terrain rider")
