extends GutTest

## #1806: Lightning's Shocked go-off, the [EdgeGoOff] on both of Lightning's
## bands in `elements/defs/lightning.tres`. A node whose post-land Charge is
## past T arcs to every node within L hops (L on the ladder count > L^exp × T),
## spends 1 Charge per node reached and, on the transfer default, moves each
## spent stack onto the node it reached. The gather (#1798) owns the chains,
## the once-per-node set, the generations and the centre landing; these tests
## pin Lightning's answers through it.
##
## Knobs are read off the def's instance (share, ladder_exponent), never as
## literals. T is t_per_degree × degree, read per node. Ice's bands are swapped
## for one test band holding a logging [Admits] where a test needs a node to
## answer an admit or a read (Ice ships none yet), restored in after_each.

const _RAW := 4.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _saved: Array = []
var _ice_bands: Array[ElementBand] = []


## Admits every copy unless [member refuse] names its node; logs each admit's
## node and generation; its read ends the paths at the nodes in [member ends_at].
class _LogAdmits extends Admits:
	var refuse: Dictionary = {}
	var ends_at: Dictionary = {}
	var admitted: Array = []

	func admit(node: SkillNode, _before: TerrainRead, arrival: Arrival) -> bool:
		admitted.append([node, arrival.generation])
		return not refuse.has(node)

	func read(node: SkillNode, _after: TerrainRead, _arrivals: Array[Arrival]) -> AdmitsAnswer:
		var answer := AdmitsAnswer.new()
		answer.paths_end = ends_at.has(node)
		return answer


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	var arc := _edge()
	_saved = [arc.share, arc.ladder_exponent, arc.max_level, arc.spent_charge_goes_to] if arc != null else []
	_ice_bands = _ice().bands.duplicate()
	await get_tree().process_frame


func after_each() -> void:
	var arc := _edge()
	if arc != null and _saved.size() == 4:
		arc.share = _saved[0]
		arc.ladder_exponent = _saved[1]
		arc.max_level = _saved[2]
		arc.spent_charge_goes_to = _saved[3]
	_ice().bands = _ice_bands
	CombatWorld.reset_live()


# --- fixture -------------------------------------------------------------------

func _light() -> Element:
	return ElementRoster.shared().by_id(&"lightning")


func _ice() -> Element:
	return ElementRoster.shared().by_id(&"ice")


func _edge() -> EdgeGoOff:
	return _light().bands[0].go_off as EdgeGoOff


## Nodes linked by index pairs, spread out (an arc is hop-bound, never a radius).
func _graph(pairs: Array) -> Array[SkillNode]:
	var count := 0
	for p in pairs:
		count = maxi(count, maxi(int(p[0]), int(p[1])) + 1)
	var pos := {}
	for i in count:
		pos[i] = Vector2(i * 3000.0, 0.0)
	return _w.build(pairs, pos)


## A line of [param n] nodes.
func _line(n: int) -> Array[SkillNode]:
	var pairs: Array = []
	for i in n - 1:
		pairs.append([i, i + 1])
	return _graph(pairs)


func _own(nodes: Array) -> void:
	_w.allocate(_red, nodes)
	await get_tree().process_frame


func _combat(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n)


func _charge(n: SkillNode) -> int:
	return _combat(n).charge()


func _t(n: SkillNode) -> int:
	return _combat(n).terrain_threshold()


func _set_charge(n: SkillNode, to: int) -> void:
	_combat(n).add_terrain(_light(), to - _charge(n))


## [param n] Frozen (Cold past T) with [param admits] on Ice's one test band.
func _freeze(nodes: Array, admits: Admits) -> void:
	var band := ElementBand.new()
	band.admits = admits
	var bands: Array[ElementBand] = [band]
	_ice().bands = bands
	for n: SkillNode in nodes:
		_combat(n).add_terrain(_ice(), _t(n) + 1)


## A hit on [param at] by Blue: damage [constant _RAW], a Charge rider of
## [param charge] when > 0, a Curse rider when [param curse].
func _hit(at: SkillNode, charge := 0, curse := false) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var span: Array[HitInstance] = [d]
	if curse:
		var c := StatusInstance.new()
		c.def = preload("res://effects/status/curse.tres")
		c.power = 1.0
		c.raw = true
		span.append(c)
	if charge > 0:
		var s := StatusInstance.new()
		s.def = _light().terrain
		s.power = float(charge)
		s.raw = true
		span.append(s)
	for hit in span:
		hit.target = at
		hit.attacker = _blue
		hit.schedule_index = 0
	return span


func _land(span: Array[HitInstance]) -> Array[HitInstance]:
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return all


func _on(hits: Array, n: SkillNode) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h.target == n)


## One landing is one damage entry.
func _landings(hits: Array, n: SkillNode) -> int:
	return _on(hits, n).filter(func(h: HitInstance) -> bool: return h is DamageInstance).size()


func _curses(hits: Array, n: SkillNode) -> int:
	return _on(hits, n).filter(func(h: HitInstance) -> bool:
		return h is StatusInstance and h.def.id == &"curse").size()


func _read(charge: int, t: int, cap := 1000) -> TerrainRead:
	var r := TerrainRead.new()
	r.charge = charge
	r.threshold = t
	r.cap = cap
	return r


func _reached(result: GoOffResult) -> Dictionary:
	var out := {}
	for r: GoOffResult.Reach in result.reached:
		out[r.node] = r
	return out


# --- 1a: the subclass, called directly -------------------------------------------

## A diamond X–P, X–Q, P–R, Q–R plus a tail R–S: R hangs behind P and Q.
func _diamond() -> Array[SkillNode]:
	return _graph([[0, 1], [0, 2], [1, 3], [2, 3], [3, 4]])


func test_the_shocked_band_holds_an_edge_go_off() -> void:
	assert_not_null(_edge(), "Lightning's Shocked band holds an EdgeGoOff")


func test_the_arc_answers_cost_transfer_depth_ring_share_and_no_damage() -> void:
	var arc := _edge()
	if arc == null:
		return
	var g := _diamond()
	var x := g[0]
	var t := 3
	var lv2 := int(pow(2, arc.ladder_exponent)) * t + 1
	var result := arc.fire(x, _read(lv2, t))
	var got := _reached(result)
	assert_eq(got.size(), 3, "level 2 reaches P, Q (1 hop) and R (2 hops), never S or X")
	assert_false(got.has(x), "the centre is excluded")
	assert_false(got.has(g[4]), "S is 3 hops away")
	if got.size() != 3:
		return
	assert_eq(got[g[1]].depth, 1, "P at depth 1")
	assert_eq(got[g[3]].depth, 2, "R at depth 2")
	var ring: Array = got[g[3]].ring.duplicate()
	ring.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return a.name < b.name)
	assert_eq(ring, [g[1], g[2]], "R hangs behind both P and Q")
	assert_true(got[g[1]].ring.is_empty(), "a depth-1 node hangs behind nothing")
	for n in [g[1], g[2], g[3]]:
		assert_eq(int(result.cost.get(n, 0)), 1, "1 Charge per node reached")
		assert_eq(int(result.transfer.get(n, 0)), 1, "1 stack lands on each node reached")
	assert_eq(result.spend(), 3, "spend = the number reached")
	assert_eq(result.share, arc.share, "share is the instance's")
	assert_eq(result.own_damage, 0.0, "no own damage")
	arc.spent_charge_goes_to = EdgeGoOff.SpentChargeGoesTo.VOID
	assert_true(arc.fire(x, _read(lv2, t)).transfer.is_empty(), "Void names no transfer")


# --- 2: the ladder, 2a: the level entry ------------------------------------------

func test_the_ladder_reads_level_l_past_l_to_the_exp_times_t() -> void:
	var arc := _edge()
	if arc == null:
		return
	var t := 3
	for exp_ in [2, 3]:
		arc.ladder_exponent = exp_
		var step := int(pow(2, exp_)) * t
		assert_eq(arc.level_of(_read(t, t)), 0, "≤ T is inert")
		assert_eq(arc.level_of(_read(t + 1, t)), 1, "past T is level 1")
		assert_eq(arc.level_of(_read(step, t)), 1, "at 2^exp × T still level 1")
		assert_eq(arc.level_of(_read(step + 1, t)), 2, "past 2^exp × T is level 2")
	arc.ladder_exponent = 2
	arc.max_level = 2
	assert_eq(arc.level_of(_read(9 * t + 1, t)), 2, "max_level caps the level read off the count")


func test_a_level_2_arc_reaches_two_hops_and_spends_that_count() -> void:
	var arc := _edge()
	if arc == null:
		return
	var g := _line(7)
	var c := g[3]
	var t := 3
	var lv1 := arc.fire(c, _read(t + 1, t))
	var lv2 := arc.fire(c, _read(int(pow(2, arc.ladder_exponent)) * t + 1, t))
	assert_eq(_reached(lv1).size(), 2, "level 1: the two neighbours")
	assert_eq(_reached(lv2).size(), 2 * _reached(lv1).size(), "level 2 on a line: twice level 1's reach")
	assert_eq(lv2.spend(), _reached(lv2).size(), "spend = the count reached")


func test_an_added_level_is_one_go_off_paying_the_solo_cost() -> void:
	var arc := _edge()
	if arc == null:
		return
	var g := _line(7)
	var c := g[3]
	var t := 3
	var read := _read(t + 1, t)
	var plain := arc.fire(c, read)
	var zero := arc.fire_level_in(null, c, read, 0)
	assert_eq(_reached(zero).keys(), _reached(plain).keys(), "N = 0 is the plain call")
	assert_eq(zero.spend(), plain.spend(), "N = 0 spends as the plain call")
	var added := arc.fire_level_in(null, c, read, 1)
	var got := _reached(added)
	assert_eq(got.size(), 4, "level 1 + 1: every node within 2 hops, one entry each")
	assert_eq(added.reached.size(), got.size(), "one Reach per node, never two")
	assert_eq(added.spend(), plain.spend(), "the node pays its solo (level-1) cost")
	assert_eq(int(added.cost.get(g[1], 0)), 0, "a node only the added level reaches costs nothing")


# --- 1, 1b: the whole hit -----------------------------------------------------------

## Y–X–Z: X at T holding [param held] Charge before a hit carrying +1 Charge
## and Curse. Y is left unallocated.
func _yxz(held_off_t: int) -> Array:
	var g := _line(3)
	var y := g[0]
	var x := g[1]
	var z := g[2]
	await _own([x, z])
	_set_charge(x, _t(x) + held_off_t)
	return [y, x, z]


func test_a_hit_tipping_past_t_arcs_both_neighbours_and_lands_the_whole_hit() -> void:
	var arc := _edge()
	if arc == null:
		return
	var got: Array = await _yxz(0)
	var y: SkillNode = got[0]
	var x: SkillNode = got[1]
	var z: SkillNode = got[2]
	assert_lt(1 + 1, _t(y) + 1, "fixture: Y stays ≤ T after its rider and transfer")
	var t_x := _t(x)
	var all := _land(_hit(x, 1, true))
	assert_eq(_landings(all, x), 2, "X: the hit and its arc's centre landing")
	assert_eq(_curses(all, x), 2, "Curse on the hit and on the centre landing (atomic 3)")
	assert_eq(_landings(all, y), 1, "Y, unallocated, takes one copy")
	assert_eq(_landings(all, z), 1, "Z takes one copy")
	assert_eq(_curses(all, y), 1, "Curse once on each neighbour")
	assert_eq(_charge(x), t_x + 1 - 2, "X lands +1 once, then spends 1 per neighbour, under T")
	var rider := int(ceil(1 * arc.share))
	assert_eq(_charge(y), rider + 1, "Y: the copy's rider and the transferred stack")
	assert_eq(_charge(z), rider + 1, "Z: the copy's rider and the transferred stack")


func test_a_hit_leaving_charge_at_t_lands_plainly() -> void:
	var got: Array = await _yxz(-1)
	var x: SkillNode = got[1]
	var t_x := _t(x)
	var all := _land(_hit(x, 1, true))
	assert_eq(_landings(all, x), 1, "one landing")
	assert_eq(_landings(all, got[0]) + _landings(all, got[2]), 0, "no copy")
	assert_eq(_charge(x), t_x, "no spend")
	assert_eq(_charge(got[2]), 0, "nothing reaches Z")


func test_on_void_no_reached_node_gains_beyond_the_rider() -> void:
	var arc := _edge()
	if arc == null:
		return
	arc.spent_charge_goes_to = EdgeGoOff.SpentChargeGoesTo.VOID
	var got: Array = await _yxz(0)
	var x: SkillNode = got[1]
	var t_x := _t(x)
	_land(_hit(x, 1))
	assert_eq(_charge(got[2]), int(ceil(1 * arc.share)), "Z: the rider only")
	assert_eq(_charge(x), t_x + 1 - 2, "X still pays 1 per neighbour")


func test_an_absorbed_copy_still_lands_its_charge_and_the_transfer() -> void:
	var arc := _edge()
	if arc == null:
		return
	var got: Array = await _yxz(0)
	var y: SkillNode = got[0]
	var x: SkillNode = got[1]
	await _own([y])
	var admits := _LogAdmits.new()
	admits.refuse[y] = true
	_freeze([y], admits)
	var t_x := _t(x)
	var all := _land(_hit(x, 1))
	assert_eq(_landings(all, y), 0, "Y absorbs the arc's copy")
	assert_eq(_charge(x), t_x + 1 - 2, "X still spends 2")
	assert_eq(_charge(y), int(ceil(1 * arc.share)) + 1, "Y's Charge rises by the rider and the transfer")


# --- 1: the wire ---------------------------------------------------------------------

func test_a_shocked_line_hands_every_stack_back() -> void:
	var g := _line(5)
	await _own(g)
	var before := {}
	for n in g:
		_set_charge(n, _t(n) + 1)
		before[n] = _charge(n)
	var all := _land(_hit(g[2]))
	for n in g:
		assert_eq(_charge(n), before[n], "%s gives one stack per neighbour and gets one back" % n.name)
	assert_eq(_landings(all, g[2]), 4, "C: the hit, its centre landing, B's and D's arcs back")
	assert_eq(_landings(all, g[1]), 3, "B: C's arc, its centre landing, A's arc back")
	assert_eq(_landings(all, g[3]), 3, "D likewise")
	assert_eq(_landings(all, g[0]), 2, "A: B's arc and its centre landing")
	assert_eq(_landings(all, g[4]), 2, "E likewise")


# --- 3: chains and the re-laid wire ---------------------------------------------------

func test_a_charge_rider_relays_ceil_r_times_share_on_every_node_reached() -> void:
	var arc := _edge()
	if arc == null:
		return
	for s in [1.0, 0.5]:
		arc.share = s
		CombatWorld.reset_live()
		var g := _line(3)
		await _own(g)
		var r := 3
		_set_charge(g[1], _t(g[1]) + 1 - r)
		_land(_hit(g[1], r))
		assert_eq(_charge(g[0]), int(ceil(r * s)) + 1, "share %s: ceil(r × s) plus the transfer" % s)


func test_a_copy_on_a_shocked_neighbour_arcs_once_in_turn() -> void:
	var g := _line(3)
	await _own(g)
	var x := g[0]
	var y := g[1]
	_set_charge(x, _t(x))
	_set_charge(y, _t(y) + 1)
	var all := _land(_hit(x, 1))
	assert_eq(_landings(all, y), 2, "Y: X's copy and its own arc's centre landing")
	assert_eq(_landings(all, g[2]), 1, "W: Y's copy")
	assert_eq(_landings(all, x), 3, "X: the hit, its centre landing, Y's arc back (no second go-off)")


# --- 1c: the overflow band -------------------------------------------------------------

func test_the_overflow_band_answers_as_shocked() -> void:
	var bands := _light().bands
	assert_true(is_same(bands[-1].go_off, bands[0].go_off), "the overflow band's go_off is Shocked's instance")
	assert_eq(bands[-1].travel, bands[0].travel, "same travel verb")
	assert_eq(bands[-1].conduct_cost, bands[0].conduct_cost, "same conduct cost")
	assert_gt(bands[0].conduct_cost, 0, "the Shocked band conducts at a cost")


func test_past_the_cap_the_level_reads_the_whole_count() -> void:
	var arc := _edge()
	if arc == null:
		return
	var g := _line(7)
	await _own(g)
	var c := g[3]
	var lv2 := int(pow(2, arc.ladder_exponent)) * _t(c) + 1
	assert_lt(_combat(c).terrain_cap(), lv2, "fixture: 4T + 1 is past the cap")
	_set_charge(c, lv2 - 1)
	var all := _land(_hit(c, 1))
	for n in [g[1], g[2], g[4], g[5]]:
		assert_gt(_landings(all, n), 0, "%s within 2 hops is reached" % n.name)
	assert_eq(_landings(all, g[0]) + _landings(all, g[6]), 0, "3 hops out is not")
	assert_eq(_charge(c), lv2 - 4, "spends the 4 reached")


# --- 3a: generations and the arc paying for what it reaches -----------------------------

## Z–Y–X–W: X past 4T after its hit's rider, level 2; Y, W, Z Frozen under a
## logging Admits (admits every copy) whose read ends paths at [param ends].
func _zyxw(ends: bool) -> Array:
	var g := _line(4)
	var z := g[0]
	var y := g[1]
	var x := g[2]
	var w := g[3]
	await _own(g)
	var admits := _LogAdmits.new()
	if ends:
		admits.ends_at[y] = true
	_freeze([y, w, z], admits)
	_set_charge(x, int(pow(2, _edge().ladder_exponent)) * _t(x))
	return [z, y, x, w, admits]


func test_a_two_hop_arc_advances_one_hop_per_generation() -> void:
	if _edge() == null:
		return
	var got: Array = await _zyxw(false)
	var x: SkillNode = got[2]
	var before := _charge(x) + 1
	var all := _land(_hit(x, 1))
	var gen := {}
	for e: Array in got[4].admitted:
		gen[e[0]] = e[1]
	assert_eq(gen.get(got[1], -1), 1, "Y one above the hit")
	assert_eq(gen.get(got[3], -1), 1, "W one above the hit")
	assert_eq(gen.get(got[0], -1), 2, "Z two above")
	assert_eq(_charge(x), before - 3, "X spends 3")
	assert_eq(_landings(all, got[0]), 1, "Z takes one entry")


func test_an_arc_whose_ring_ends_pays_only_for_what_it_reaches() -> void:
	if _edge() == null:
		return
	var got: Array = await _zyxw(true)
	var z: SkillNode = got[0]
	var x: SkillNode = got[2]
	var before := _charge(x) + 1
	var all := _land(_hit(x, 1))
	assert_eq(_landings(all, z), 0, "Z, behind the ended Y, takes no entry")
	assert_eq(_charge(x), before - 2, "X spends 2 (Y and W)")
	assert_eq(_charge(z), 0, "Z gains no transferred stack")
