extends GutTest

## The one go-off pay rule (ADR 0097 §2-§5): a primed node that goes off voids
## [member GoOff.void_floor] and pays 1 more per node it reaches; each reached
## node takes +1 of the element's terrain on the "Reached node" default
## ([member EdgeGoOff.spent_charge_goes_to], [member DiscGoOff.spent_heat_goes_to]).
## A disc that reaches nobody still voids its floor while
## [member GoOff.floor_when_unreached] holds. A cast shape running alone on a
## node that is not primed pays nothing.
##
## Gather cases run through Fire's and Lightning's shared defs, their knobs
## saved in before_each and restored in after_each; unit cases use a bare
## instance. T is read per node, never a literal. Every disc fixture node links
## to a far anchor (degree 1, T > 0), so a +1 never primes it.

const _RAW := 4.0
const _FAR := 20000.0

var _w: TestWorld
var _red: Entity
var _blue: Entity
var _saved_disc: Array = []
var _saved_edge: Array = []


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_red = _w.add_entity("Red")
	_blue = _w.add_entity("Blue")
	var d := _disc()
	_saved_disc = [d.void_floor, d.floor_when_unreached, d.spent_heat_goes_to]
	var e := _edge()
	_saved_edge = [e.void_floor, e.floor_when_unreached, e.spent_charge_goes_to]
	await get_tree().process_frame


func after_each() -> void:
	var d := _disc()
	d.void_floor = _saved_disc[0]
	d.floor_when_unreached = _saved_disc[1]
	d.spent_heat_goes_to = _saved_disc[2]
	var e := _edge()
	e.void_floor = _saved_edge[0]
	e.floor_when_unreached = _saved_edge[1]
	e.spent_charge_goes_to = _saved_edge[2]
	CombatWorld.reset_live()


# --- fixture -------------------------------------------------------------------

func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


func _light() -> Element:
	return ElementRoster.shared().by_id(&"lightning")


func _disc() -> DiscGoOff:
	return _fire().bands[0].go_off as DiscGoOff


func _edge() -> EdgeGoOff:
	return _light().bands[0].go_off as EdgeGoOff


func _combat(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n)


func _t(n: SkillNode) -> int:
	return _combat(n).terrain_threshold()


func _heat(n: SkillNode) -> int:
	return _combat(n).terrain_t()


func _charge(n: SkillNode) -> int:
	return _combat(n).charge()


func _set_heat(n: SkillNode, to: int) -> void:
	_combat(n).add_terrain(_fire(), to - _heat(n))


func _set_charge(n: SkillNode, to: int) -> void:
	_combat(n).add_terrain(_light(), to - _charge(n))


func _sum(nodes: Array, f: Callable) -> int:
	var total := 0
	for n: SkillNode in nodes:
		total += int(f.call(n))
	return total


## Nodes linked by index pairs, spread out (an arc is hop-bound, never a radius).
func _graph(pairs: Array) -> Array[SkillNode]:
	var count := 0
	for p in pairs:
		count = maxi(count, maxi(int(p[0]), int(p[1])) + 1)
	var pos := {}
	for i in count:
		pos[i] = Vector2(i * 3000.0, 0.0)
	return _w.build(pairs, pos)


## A node [param edge] px (hitbox edge) from the origin at [param angle], linked
## to its own far anchor in the same direction (degree 1, outside any disc).
## Appends both to [param all].
func _disc_node(id: StringName, edge: float, angle: float, all: Array) -> SkillNode:
	var n := _w.add_node(id)
	var dir := Vector2.from_angle(angle)
	n.global_position = dir * (edge + n.radius) if edge >= 0.0 else Vector2.ZERO
	var anchor := _w.add_node(StringName("%s_anchor" % id))
	anchor.global_position = n.global_position + dir * _FAR
	_w.link(n, anchor)
	all.append(n)
	all.append(anchor)
	return n


func _own(nodes: Array) -> void:
	_w.allocate(_red, nodes)
	await get_tree().process_frame


## A bare hit on [param at] by Blue: damage only, no rider.
func _hit(at: SkillNode) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.amount = _RAW
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	d.target = at
	d.attacker = _blue
	d.schedule_index = 0
	var span: Array[HitInstance] = [d]
	return span


func _land(span: Array[HitInstance]) -> Array[HitInstance]:
	var all: Array[HitInstance] = span.duplicate()
	HitGather.stage_one(span.duplicate(), CombatWorld.live(), HitQueue.over(all))
	return all


## A Burning centre C (Heat T + 2, excess 2) whose disc reaches exactly D
## nodes at 0 Heat. Returns [C, [reached], [every node, anchors included]].
func _burning_star(d: int) -> Array:
	var all: Array = []
	var c := _disc_node(&"C", -1.0, PI, all)
	var radius := _disc().radius_at(c, 2)
	var reached: Array = []
	for i in d:
		reached.append(_disc_node(StringName("N%d" % i), 0.3 * radius, TAU * i / float(d) + 0.3, all))
	await _own(all)
	_set_heat(c, _t(c) + 2)
	return [c, reached, all]


## A Lightning star: centre of degree 3 at Charge T + 1 (level 1), leaves at 0.
func _charged_star() -> Array[SkillNode]:
	var g := _graph([[0, 1], [0, 2], [0, 3]])
	await _own(g)
	_set_charge(g[0], _t(g[0]) + 1)
	return g


# --- 1: the owner's arithmetic, Lightning ------------------------------------------

func test_a_level_1_arc_voids_the_floor_and_moves_one_per_leaf() -> void:
	var g: Array[SkillNode] = await _charged_star()
	var c := g[0]
	var n := _charge(c)
	for leaf in g.slice(1):
		assert_lt(1, _t(leaf) + 1, "fixture: a leaf stays at or under T after its +1")
	_land(_hit(c))
	assert_eq(_charge(c), n - 3 - 1, "C: N − D − 1")
	for leaf in g.slice(1):
		assert_eq(_charge(leaf), 1, "each leaf takes +1")
	assert_eq(_sum(g, _charge), n - 1, "exactly the floor is voided")


# --- 2: the owner's arithmetic, Fire -------------------------------------------------

func test_a_burning_disc_voids_the_floor_and_moves_one_heat_per_reached_node() -> void:
	var got: Array = await _burning_star(2)
	var c: SkillNode = got[0]
	var all: Array = got[2]
	var n := _heat(c)
	var before := _sum(all, _heat)
	_land(_hit(c))
	assert_eq(_heat(c), n - 2 - 1, "C: N − D − 1")
	for r: SkillNode in got[1]:
		assert_eq(_heat(r), 1, "each reached node takes +1 Heat")
	assert_eq(_sum(all, _heat), before - 1, "exactly the floor is voided")


# --- 3: the floor adds on a shaped Burning node --------------------------------------

func test_a_shaped_burning_node_pays_the_floor_plus_its_solo_reach() -> void:
	var disc := DiscGoOff.new()
	var all: Array = []
	var c := _disc_node(&"C", -1.0, PI, all)
	var solo := disc.disc_radius(4, c.radius)
	var s1 := _disc_node(&"S1", 0.3 * solo, 0.0, all)
	var s2 := _disc_node(&"S2", 0.5 * solo, PI / 2.0, all)
	await _own(all)
	_set_heat(c, _t(c) + 4)
	var result := disc.fire_shaped_in(null, c, TerrainRead.of(_combat(c), c), 15.0)
	assert_eq(result.cost.size(), 2, "fixture: the solo disc holds S1 and S2")
	assert_eq(result.spend(), disc.void_floor + 2, "the floor plus 1 per solo node")
	assert_eq(result.nodeless_cost, disc.void_floor, "the floor is nodeless")
	assert_eq(result.transfer.get(s1, 0), 1, "S1 takes +1 Heat")
	assert_eq(result.transfer.get(s2, 0), 1, "S2 takes +1 Heat")


# --- 4: an empty reach ---------------------------------------------------------------

func test_a_burning_node_reaching_nobody_voids_its_floor_and_makes_no_entry() -> void:
	var got: Array = await _burning_star(0)
	var c: SkillNode = got[0]
	var n := _heat(c)
	var span := _hit(c)
	var all := _land(span)
	assert_eq(_heat(c), n - _disc().void_floor, "the floor is voided")
	assert_eq(all.size(), span.size(), "no entry, no centre copy, no mark")


func test_with_floor_when_unreached_off_a_lone_burning_node_is_unchanged() -> void:
	_disc().floor_when_unreached = false
	var got: Array = await _burning_star(0)
	var c: SkillNode = got[0]
	var n := _heat(c)
	var span := _hit(c)
	var all := _land(span)
	assert_eq(_heat(c), n, "no go-off, no spend")
	assert_eq(all.size(), span.size(), "no entry")


# --- 5: the knobs --------------------------------------------------------------------

func test_on_void_the_per_reached_heat_is_voided_too() -> void:
	_disc().spent_heat_goes_to = DiscGoOff.SpentHeatGoesTo.VOID
	var got: Array = await _burning_star(2)
	var c: SkillNode = got[0]
	var all: Array = got[2]
	var n := _heat(c)
	var before := _sum(all, _heat)
	_land(_hit(c))
	assert_eq(_heat(c), n - 2 - 1, "C pays the same bill")
	for r: SkillNode in got[1]:
		assert_eq(_heat(r), 0, "no reached node gains")
	assert_eq(_sum(all, _heat), before - 3, "board Heat drops by D + 1")


func test_a_floor_of_0_pays_per_reached_only_for_fire() -> void:
	_disc().void_floor = 0
	var got: Array = await _burning_star(2)
	var c: SkillNode = got[0]
	var all: Array = got[2]
	var n := _heat(c)
	var before := _sum(all, _heat)
	_land(_hit(c))
	assert_eq(_heat(c), n - 2, "C: N − D")
	assert_eq(_sum(all, _heat), before, "nothing voided")


func test_a_floor_of_0_pays_per_reached_only_for_lightning() -> void:
	_edge().void_floor = 0
	var g: Array[SkillNode] = await _charged_star()
	var n := _charge(g[0])
	_land(_hit(g[0]))
	assert_eq(_charge(g[0]), n - 3, "C: N − D")
	assert_eq(_sum(g, _charge), n, "nothing voided")


# --- 6: a shape alone pays nothing ---------------------------------------------------

func test_a_lightning_shape_on_a_node_not_shocked_spends_nothing() -> void:
	var g: Array[SkillNode] = await _charged_star()
	_set_charge(g[0], 0)
	var edge := EdgeGoOff.new()
	var result := edge.fire_level_in(null, g[0], TerrainRead.of(_combat(g[0]), g[0]), 1)
	assert_eq(result.reached.size(), 3, "fixture: the shape reaches the leaves")
	assert_eq(result.spend(), 0, "no spend, no floor")
	assert_true(result.transfer.is_empty(), "no transfer")


func test_a_fire_shape_on_a_node_not_burning_spends_nothing() -> void:
	var got: Array = await _burning_star(2)
	var c: SkillNode = got[0]
	_set_heat(c, 0)
	var disc := DiscGoOff.new()
	var result := disc.fire_shaped_in(null, c, TerrainRead.of(_combat(c), c), 4.0)
	assert_false(result.reached.is_empty(), "fixture: the shape reaches someone")
	assert_eq(result.spend(), 0, "no spend, no floor")
	assert_true(result.transfer.is_empty(), "no transfer")


# --- 8: the wire of four -------------------------------------------------------------

func test_a_wire_of_four_goes_off_once_each_and_voids_four() -> void:
	var g := _graph([[0, 1], [1, 2], [2, 3], [3, 4], [4, 5]])
	await _own(g)
	var t := _t(g[1])
	for i in range(1, 5):
		_set_charge(g[i], t + 2)
	var before := _sum(g, _charge)
	_land(_hit(g[1]))
	assert_eq(_charge(g[1]), t, "A: no longer Shocked")
	assert_eq(_charge(g[2]), t + 1, "B")
	assert_eq(_charge(g[3]), t + 1, "C")
	assert_eq(_charge(g[4]), t, "D: no longer Shocked")
	assert_eq(_charge(g[0]), 1, "X takes +1")
	assert_eq(_charge(g[5]), 1, "Y takes +1")
	assert_eq(_sum(g, _charge), before - 4, "each of the four voids its floor")
