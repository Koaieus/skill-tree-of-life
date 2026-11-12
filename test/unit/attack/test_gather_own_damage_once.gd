extends GutTest

## #1800 (U3): a hit with two DAMAGE rows reached by a go-off carries the
## go-off's own damage once per entry, on the entry's first damage row, in both
## the push ([method HitGather._push]) and the arrival's amount
## ([method HitGather._amount]). Burning's disc is the go-off; its knobs are
## read off Fire's instance and its mark, never as literals.
##
## Every fixture node is Red's and the attacker is Blue, so each reached node
## passes the head's HOSTILE target mask. Each node links to its own far
## anchor, so its degree is 1 and its threshold T > 0.

const _RAW := 4.0
## Each node's anchor sits this far below it: outside any disc.
const _FAR := 20000.0

var _w: TestWorld
var _red: Entity
var _blue: Entity


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	await get_tree().process_frame


func after_each() -> void:
	CombatWorld.reset_live()


# --- fixture -------------------------------------------------------------------

func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


## Fire's Burning disc, asserted present.
func _disc() -> DiscGoOff:
	var disc := _fire().bands[0].go_off as DiscGoOff
	assert_not_null(disc, "Fire's Burning band holds a DiscGoOff")
	return disc


## A node at [param pos], linked to its own far anchor (degree 1, so T > 0).
func _at(id: StringName, pos: Vector2) -> SkillNode:
	var n := _w.add_node(id)
	n.global_position = pos
	var anchor := _w.add_node(StringName("%s_anchor" % id))
	anchor.global_position = pos + Vector2(0.0, _FAR)
	_w.link(n, anchor)
	return n


## A node whose hitbox edge sits [param edge] px due east of [param from]'s centre.
func _east(from: SkillNode, id: StringName, edge: float) -> SkillNode:
	var n := _at(id, from.global_position)
	n.global_position = from.global_position + Vector2(edge + n.radius, 0.0)
	return n


## Red takes [param nodes]; the board settles.
func _own(nodes: Array) -> void:
	_w.allocate(_red, nodes)
	await get_tree().process_frame


func _combat(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n)


func _heat(n: SkillNode) -> int:
	return _combat(n).terrain_t()


func _t(n: SkillNode) -> int:
	return _combat(n).terrain_threshold()


func _set_heat(n: SkillNode, to: int) -> void:
	_combat(n).add_terrain(_fire(), to - _heat(n))


## The formula, off the instance's knobs (never the function under test).
func _r(disc: DiscGoOff, power: float, node_radius: float) -> float:
	return disc.radius_a * (sqrt(power) + disc.radius_b) * node_radius


## A hit on [param at] by Blue: TWO damage rows of [constant _RAW] and, when
## [param heat] > 0, a Heat rider of that power (Burning's go-off seat).
func _hit(at: SkillNode, heat := 0) -> Array[HitInstance]:
	var span: Array[HitInstance] = []
	for i in 2:
		var d := DamageInstance.new()
		d.amount = _RAW
		d.type = DamageInstance.Type.TRUE
		d.is_head = i == 0
		span.append(d)
	if heat > 0:
		var h := StatusInstance.new()
		h.def = _fire().terrain
		h.power = float(heat)
		h.raw = true
		span.append(h)
	for hit in span:
		hit.target = at
		hit.attacker = _blue
		hit.schedule_index = 0
		hit.target_mask = SkillNode.Ownership.HOSTILE
	return span


## Stage one on the live world: the hit plus every entry it gathered.
func _land(span: Array[HitInstance]) -> Array[HitInstance]:
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return all


func _on(hits: Array, n: SkillNode) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h.target == n)


## One landing is one damage entry.
func _damage_of(hits: Array) -> Array:
	var out := hits.filter(func(h: HitInstance) -> bool: return h is DamageInstance) \
			.map(func(h: HitInstance) -> float: return h.amount)
	out.sort()
	return out


## `[C, N, all]`: a two-damage hit with a Heat rider of 1 on C (Burning at
## T + 1, so excess 2 after the rider) whose disc reaches N alone; N at 0 Heat.
func _whole_hit(disc: DiscGoOff) -> Array:
	var c := _at(&"C", Vector2.ZERO)
	var n := _east(c, &"N", 0.5 * _r(disc, 2, c.radius))
	await _own([c, n])
	_set_heat(c, _t(c) + 1)
	assert_lt(1, _t(n) + 1, "fixture: N stays unprimed after its copy")
	return [c, n, _land(_hit(c, 1))]


# --- the own damage lands once per entry ----------------------------------------

func test_two_damage_rows_carry_the_own_damage_once_per_entry() -> void:
	var disc := _disc()
	if disc == null:
		return
	assert_gt(disc.damage_per_power, 0.0, "fixture: the def authors own damage")
	var got: Array = await _whole_hit(disc)
	var c: SkillNode = got[0]
	var n: SkillNode = got[1]
	var all: Array = got[2]
	var copies := _on(all, n)
	assert_eq(copies.size(), 2, "N takes the go-off's two damage rows")
	var own := 0.0
	for h: HitInstance in copies:
		assert_not_null(h.blast_mark, "each copy carries the go-off's mark")
		if h.blast_mark != null:
			own = disc.damage_per_power * h.blast_mark.power
	assert_gt(own, 0.0, "fixture: the go-off carries own damage")
	var total := 0.0
	for amount in _damage_of(copies):
		total += amount
	assert_almost_eq(total, (_RAW + _RAW) * disc.share + own, 0.0001,
			"N's entry totals both rows × share plus the own damage once")
	var centre := _on(all, c).filter(func(h: HitInstance) -> bool:
		return h is DamageInstance and h.blast_mark != null)
	assert_eq(centre.size(), 2, "C takes the go-off's two centre rows")
	var centre_total := 0.0
	for amount in _damage_of(centre):
		centre_total += amount
	assert_almost_eq(centre_total, (_RAW + _RAW) * disc.share + own, 0.0001,
			"C's centre landing totals both rows × share plus the own damage once")
