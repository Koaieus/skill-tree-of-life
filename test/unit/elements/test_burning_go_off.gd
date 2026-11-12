extends GutTest

## #1800 (U3): Burning's disc, the [DiscGoOff] instance on Fire's bands in
## `elements/defs/fire.tres`. Power is Heat's excess over T after the hit's
## Heat rider lands, the radius is [method DiscGoOff.disc_radius] off the
## origin node's own radius, the spend is 1 Heat per other node reached (none
## reached: no go-off), and the own damage is `damage_per_power × power`.
##
## The knobs (A, B, share, damage_per_power) are read off Fire's instance,
## never as literals. A node is reached when its hitbox touches the disc
## ([EuclideanRangeFinder]: centre distance less the node's own radius), so
## "a node at d" sits with its hitbox edge d from the centre ([method _east]).
## Every fixture node is Red's and the attacker is Blue, so each reached node
## passes the hit's target mask. Each node links to its own far anchor, so its
## degree is 1 and its threshold T > 0.

const _RAW := 4.0
const _POISON := 3.0
## Each node's anchor sits this far below it: outside any disc.
const _FAR := 20000.0
## Rows of [method test_the_disc_reaches_by_the_radius_function_from_its_own_node]
## sit this far apart on y, so no disc reaches another row's nodes.
const _ROW_GAP := 5000.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
## Fire's instance's knobs at before_each, restored at after_each.
var _saved: Array = []


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	var disc := _fire().bands[0].go_off as DiscGoOff
	_saved = [disc.radius_a, disc.radius_b, disc.damage_per_power, disc.share] if disc != null else []
	await get_tree().process_frame


func after_each() -> void:
	var disc := _fire().bands[0].go_off as DiscGoOff
	if disc != null and _saved.size() == 4:
		disc.radius_a = _saved[0]
		disc.radius_b = _saved[1]
		disc.damage_per_power = _saved[2]
		disc.share = _saved[3]
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


## A hit on [param at] by Blue: damage [constant _RAW], Poison
## [constant _POISON] and, when [param heat] > 0, a Heat rider of that power.
func _hit(at: SkillNode, heat := 0) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var poison := StatusInstance.new()
	poison.def = preload("res://effects/status/poison.tres")
	poison.power = _POISON
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
		hit.attacker = _blue
		hit.schedule_index = 0
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


func _poison_of(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is StatusInstance and h.def.id == &"poison") \
			.map(func(h: HitInstance) -> float: return h.power)


func _heat_riders(hits: Array) -> int:
	return hits.filter(func(h: HitInstance) -> bool: return h is StatusInstance and h.def == _fire().terrain).size()


## The marks on [param n]'s entries whose go-off went off at [param centre].
func _marks(hits: Array, n: SkillNode, centre: SkillNode) -> Array:
	var out: Array = []
	for h: HitInstance in _on(hits, n):
		if h.blast_mark != null and h.blast_mark.centre == centre and not out.has(h.blast_mark):
			out.append(h.blast_mark)
	return out


func _reached(result: GoOffResult) -> Array:
	return result.reached.map(func(r: GoOffResult.Reach) -> SkillNode: return r.node)


# --- 1: the disc's reach, called directly ---------------------------------------

func test_the_disc_reaches_by_the_radius_function_from_its_own_node() -> void:
	var disc := _disc()
	if disc == null:
		return
	# Row 0: excess 1, radius R. Row 1: excess 4, radius R. Row 2: excess 1, radius 2R.
	var c1 := _at(&"C1", Vector2.ZERO)
	var c4 := _at(&"C4", Vector2(0.0, _ROW_GAP))
	var c2 := _at(&"C2", Vector2(0.0, 2.0 * _ROW_GAP))
	var big := c2.radius
	c2.base_radius *= 2.0
	var r := c1.radius
	assert_almost_eq(c2.radius, 2.0 * big, 0.001, "fixture: C2's radius is 2R")
	var in1 := _east(c1, &"In1", _r(disc, 1, r) - 0.1 * r)
	var out1 := _east(c1, &"Out1", _r(disc, 1, r) + 0.1 * r)
	var wild := _east(c1, &"Wild", 0.5 * _r(disc, 1, r))
	var in4 := _east(c4, &"In4", _r(disc, 4, r) - 0.1 * r)
	var out4 := _east(c4, &"Out4", _r(disc, 4, r) + 0.1 * r)
	var in2 := _east(c2, &"In2", _r(disc, 1, c2.radius) - 0.1 * r)
	var out2 := _east(c2, &"Out2", _r(disc, 1, c2.radius) + 0.1 * r)
	await _own([c1, c4, c2, in1, out1, in4, out4, in2, out2])
	assert_almost_eq(in2.radius, r, 0.001, "fixture: the reached nodes keep radius R")
	for pair in [[c1, 1], [c4, 4], [c2, 1]]:
		_set_heat(pair[0], _t(pair[0]) + pair[1])
	var one := disc.fire_in(CombatWorld.live(), c1, TerrainRead.of(_combat(c1), c1), 0)
	var got := _reached(one)
	assert_true(got.has(in1) and got.has(wild), "excess 1 reaches the node at r − 0.1R, and an unowned one inside")
	assert_false(got.has(out1), "not the one at r + 0.1R")
	assert_false(got.has(c1), "the centre is never a reached node")
	assert_eq(got.size(), 2, "row 0's disc reaches exactly In1 and Wild")
	assert_eq(one.spend(), got.size(), "1 Heat per node reached")
	assert_eq(one.power, 1, "power is the excess")
	var four := disc.fire_in(CombatWorld.live(), c4, TerrainRead.of(_combat(c4), c4), 0)
	assert_eq(_reached(four), [in4], "excess 4 reaches r(4) − 0.1R, not r(4) + 0.1R")
	var two := disc.fire_in(CombatWorld.live(), c2, TerrainRead.of(_combat(c2), c2), 0)
	assert_eq(_reached(two), [in2], "a 2R origin sizes the disc by its own radius")
	assert_almost_eq(two.reach, _r(disc, 1, c2.radius), 0.01, "the mark's reach is the origin's disc")


func test_a_disc_spend_may_leave_heat_under_t() -> void:
	var disc := _disc()
	if disc == null:
		return
	var c := _at(&"C", Vector2.ZERO)
	var a := _east(c, &"A", 0.5 * _r(disc, 1, c.radius))
	var b := _at(&"B", Vector2.ZERO)
	b.global_position = c.global_position + Vector2(0.0, 0.5 * _r(disc, 1, c.radius) + b.radius)
	await _own([c, a, b])
	_set_heat(c, _t(c) + 1)
	_land(_hit(c))
	assert_eq(_heat(c), _t(c) + 1 - 2, "excess 1 reaching two nodes spends 2: Heat under T")


# --- 2: no reach, no go-off; riders first ----------------------------------------

func test_a_disc_reaching_no_other_node_spends_nothing_and_lands_nothing() -> void:
	var c := _at(&"C", Vector2.ZERO)
	await _own([c])
	_set_heat(c, _t(c) + 3)
	var span := _hit(c)
	var all := _land(span)
	assert_eq(all.size(), span.size(), "no copy and no centre landing")
	assert_eq(_heat(c), _t(c) + 3, "no spend")


func test_heat_at_t_after_the_rider_lands_plainly() -> void:
	var disc := _disc()
	if disc == null:
		return
	var c := _at(&"C", Vector2.ZERO)
	var n := _east(c, &"N", 0.5 * _r(disc, 1, c.radius))
	await _own([c, n])
	_set_heat(c, _t(c) - 1)
	var span := _hit(c, 1)
	var all := _land(span)
	assert_eq(all.size(), span.size(), "excess 0 after the rider: no copy")
	assert_eq(_heat(c), _t(c), "the rider lands; nothing spent")


func test_the_rider_that_tips_the_node_sets_it_off_in_that_hit() -> void:
	var disc := _disc()
	if disc == null:
		return
	var c := _at(&"C", Vector2.ZERO)
	var n := _east(c, &"N", 0.5 * _r(disc, 1, c.radius))
	await _own([c, n])
	_set_heat(c, _t(c))
	var all := _land(_hit(c, 1))
	assert_eq(_damage_of(_on(all, n)).size(), 1, "the hit that lifts T to T + 1 sets the disc off")
	assert_eq(_heat(c), _t(c), "its rider lands, then 1 Heat is spent for N")


# --- 3: power after the land; the copy's payload ---------------------------------

func test_repeated_one_heat_hits_grow_the_disc_until_it_catches_a_neighbour() -> void:
	var disc := _disc()
	if disc == null:
		return
	var c := _at(&"C", Vector2.ZERO)
	var n := _east(c, &"N", 0.5 * (_r(disc, 1, c.radius) + _r(disc, 2, c.radius)))
	await _own([c, n])
	_set_heat(c, _t(c))
	var first := _land(_hit(c, 1))
	assert_true(_on(first, n).is_empty(), "excess 1: the disc falls short of N")
	assert_eq(_heat(c), _t(c) + 1, "and spends nothing")
	var second := _land(_hit(c, 1))
	var copy := _on(second, n)
	assert_eq(_damage_of(copy), [_RAW * disc.share + disc.damage_per_power * 2],
			"excess 2 catches N: damage × share plus damage_per_power × power")
	assert_eq(_poison_of(copy), [ceilf(_POISON * disc.share)], "riders ceil(r × share)")
	assert_eq(_heat(c), _t(c) + 1, "the second rider lands, 1 Heat spent for N")


# --- 3b / 3c: the whole hit ---------------------------------------------------

## `[C, N, all]`: a hit with a Heat rider of 1 on C (Burning at T + 1, so
## excess 2 after the rider) whose disc reaches N alone; N at 0 Heat.
func _whole_hit(disc: DiscGoOff) -> Array:
	var c := _at(&"C", Vector2.ZERO)
	var n := _east(c, &"N", 0.5 * _r(disc, 2, c.radius))
	await _own([c, n])
	_set_heat(c, _t(c) + 1)
	assert_lt(1, _t(n) + 1, "fixture: N stays unprimed after its copy (Heat + h ≤ T)")
	return [c, n, _land(_hit(c, 1))]


func test_the_whole_hit_lands_once_per_channel_and_terrain_once_per_node() -> void:
	var disc := _disc()
	if disc == null:
		return
	disc.damage_per_power = 0.0
	var got: Array = await _whole_hit(disc)
	var c: SkillNode = got[0]
	var n: SkillNode = got[1]
	assert_eq(_damage_of(_on(got[2], c)), [_RAW, _RAW], "C takes its hit and its centre landing")
	assert_eq(_poison_of(_on(got[2], c)), [_POISON, _POISON], "each with Poison")
	assert_eq(_damage_of(_on(got[2], n)), [_RAW], "N takes one copy")
	assert_eq(_poison_of(_on(got[2], n)), [_POISON], "with Poison")
	assert_eq(_heat(n), 1, "N's Heat moves by h")
	assert_eq(_heat(c), _t(c) + 1 + 1 - 1, "C's Heat moves by h − 1, never 2h − 1")
	assert_eq(_heat_riders(_on(got[2], c)), 1, "C's centre landing carries no Heat rider: only the hit's own")
	assert_eq(_heat_riders(_on(got[2], n)), 0, "N's copy lands its Heat in stage one, not as a later rider")


func test_the_own_damage_rides_the_centre_landing_and_every_copy() -> void:
	var disc := _disc()
	if disc == null:
		return
	assert_gt(disc.damage_per_power, 0.0, "fixture: the def authors own damage")
	var got: Array = await _whole_hit(disc)
	var own := _RAW + disc.damage_per_power * 2
	assert_eq(_damage_of(_on(got[2], got[0])), [_RAW, own], "C's hit carries D; its centre landing D + own")
	assert_eq(_damage_of(_on(got[2], got[1])), [own], "N's copy carries D + damage_per_power × P")


# --- 4: chains ----------------------------------------------------------------

func test_a_copys_heat_sets_off_the_next_node_one_generation_later() -> void:
	var disc := _disc()
	if disc == null:
		return
	var c := _at(&"C", Vector2.ZERO)
	var r := c.radius
	var n := _east(c, &"N", _r(disc, 4, r) - 0.1 * r)
	var m := _east(n, &"M", _r(disc, 1, r) - 0.1 * r)
	await _own([c, n, m])
	_set_heat(c, _t(c) + 4 - 1)
	_set_heat(n, _t(n) + 1 - 1)
	assert_lt(1, _t(m) + 1, "fixture: M stays unprimed after its copy")
	var all := _land(_hit(c, 1))
	var from_c := _marks(all, n, c)
	var from_n := _marks(all, m, n)
	assert_eq(from_c.size(), 1, "C's disc reaches N")
	assert_eq(from_n.size(), 1, "N's disc reaches M")
	assert_true(_marks(all, c, n).is_empty(), "N's disc does not reach back to C")
	if from_c.size() == 1 and from_n.size() == 1:
		assert_eq(from_n[0].generation, from_c[0].generation + 1, "N's mark is one generation after C's")
	assert_eq(_heat(m), 1, "M's Heat moves by h: copies carry everything")
	assert_eq(_damage_of(_on(all, c)).size(), 2, "C: its hit and its centre landing")
	assert_eq(_damage_of(_on(all, n)).size(), 2, "N: C's copy and its own centre landing")
	assert_eq(_damage_of(_on(all, m)).size(), 1, "M: N's copy")
	assert_eq(_heat(n), _t(n) + 1 - 1, "N lands its copy's Heat once, then spends 1 for M")


# --- 5b: the radius seam -------------------------------------------------------

func test_disc_radius_is_a_times_root_power_plus_b_times_the_origin_radius() -> void:
	var disc := _disc()
	if disc == null:
		return
	var r := 32.0
	var a := disc.radius_a
	var b := disc.radius_b
	assert_almost_eq(disc.disc_radius(1, r), a * (1.0 + b) * r, 0.001, "power 1: A × (1 + B) × R")
	assert_almost_eq(disc.disc_radius(4, r), a * (2.0 + b) * r, 0.001, "power 4: A × (2 + B) × R")
	for p in [1, 4]:
		assert_almost_eq(disc.disc_radius(p, 2.0 * r), 2.0 * disc.disc_radius(p, r), 0.001,
				"power %d: the origin's radius scales the disc" % p)


func test_the_defs_knobs_move_the_disc_and_the_function_together() -> void:
	var disc := _disc()
	if disc == null:
		return
	var c := _at(&"C", Vector2.ZERO)
	await _own([c])
	_set_heat(c, _t(c) + 1)
	disc.radius_a = _saved[0] + 1.0
	disc.radius_b = _saved[1] + 0.5
	var want := disc.radius_a * (1.0 + disc.radius_b) * c.radius
	assert_almost_eq(disc.disc_radius(1, c.radius), want, 0.001, "the function follows A and B")
	var result := disc.fire_in(CombatWorld.live(), c, TerrainRead.of(_combat(c), c), 0)
	assert_almost_eq(result.reach, want, 0.001, "and Burning's disc with it")


# --- 5c: the overflow band ----------------------------------------------------

## The overflow band keeps Burning's travel verb and its disc (lead call,
## tentative: only its decay differs).
func test_the_overflow_band_keeps_burnings_travel() -> void:
	var bands := _fire().bands
	assert_eq(bands[-1].travel, bands[0].travel, "the overflow band keeps Burning's travel verb")


## Acceptance 5c's go-off half: past its cap k × T a node reads the overflow
## band, which answers with Burning's own disc at the whole excess, Heat − T.
func test_a_node_past_its_cap_goes_off_by_the_whole_excess() -> void:
	assert_true(is_same(_fire().bands[-1].go_off, _fire().bands[0].go_off),
			"the overflow band's go_off is Burning's instance")
	var disc := _disc()
	if disc == null:
		return
	var c := _at(&"C", Vector2.ZERO)
	var n := _east(c, &"N", 0.5 * c.radius)
	await _own([c, n])
	var t := _t(c)
	var cap := _combat(c).terrain_cap()
	assert_gt(cap, t, "fixture: the cap k × T sits past T")
	_set_heat(c, cap)
	var all := _land(_hit(c, 1))
	var marks := _marks(all, n, c)
	assert_eq(marks.size(), 1, "the overflow band's disc reaches N")
	if marks.size() == 1:
		assert_eq(marks[0].power, cap + 1 - t, "power is the whole excess, Heat − T")
		assert_almost_eq(marks[0].reach, disc.disc_radius(cap + 1 - t, c.radius), 0.01,
				"radius disc_radius(Heat − T, R)")
		assert_eq(marks[0].go_off, _fire().bands[0].identity, "the mark names Burning")
	assert_eq(_damage_of(_on(all, c)).size(), 2, "the centre landing as in 3b")
	assert_eq(_heat(c), cap + 1 - 1, "1 Heat per node reached")


# --- 7: go-off zero's values are the class defaults ------------------------------

func test_a_new_disc_keeps_go_off_zeros_values() -> void:
	var fresh := DiscGoOff.new()
	assert_eq(fresh.damage_per_power, 0.0, "no own damage by default")
	assert_eq(fresh.spend_source, DiscGoOff.Spend.SPEND_OF, "spend_of by default")
	assert_eq(fresh.power_source, DiscGoOff.Power.EXPLOSIVE_CHARGES, "go-off zero's power")
	assert_eq(fresh.radius_source, DiscGoOff.Radius.EXPLOSIVE_SPREAD, "go-off zero's radius")
