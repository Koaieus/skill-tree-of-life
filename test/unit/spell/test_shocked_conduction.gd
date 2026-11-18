extends GutTest

## A spell walk conducts through a Shocked node (Lightning's band travel
## CONDUCTS): arriving there it pays the band's `conduct_cost` in Charge and
## leaves without spending a hop, even on 0 hops left; a spread-less spell
## never conducts and pays nothing; conduction and the node's own arc fire on
## one arrival and their spends sum in the one settle of that read.
##
## Board: a line, node 0 the caster's, the rest the defender's. Resolved
## against the live world so the Charge ints read back after the cast.

const H := preload("res://test/unit/spell/spell_test_helper.gd")

var _light: Element = null
var _go_offs: Array = []
var _costs: Array = []


func before_each() -> void:
	CombatWorld.reset_live()
	# Held: an unheld roster reloads its defs and drops a swapped field.
	_light = ElementRoster.shared().by_id(&"lightning")
	_go_offs = []
	_costs = []
	for band in _light.bands:
		_go_offs.append(band.go_off)
		_costs.append(band.conduct_cost)


func after_each() -> void:
	for i in _light.bands.size():
		_light.bands[i].go_off = _go_offs[i]
		_light.bands[i].conduct_cost = _costs[i]
	CombatWorld.reset_live()


## Lightning's bands with no arc: the walk's conduction alone moves Charge.
func _no_arc() -> void:
	for band in _light.bands:
		band.go_off = null


func _shocked_cost() -> int:
	return _light.bands[0].conduct_cost


## [helper, graph, attacker, nodes] — the attacker owns 0, the defender the rest.
func _setup(adjacency: Array) -> Array:
	var helper := H.new()
	var graph := helper.make_graph(adjacency, self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.give_big_hp(atk)
	var nodes := graph.get_skill_nodes()
	var rest: Array = []
	for i in range(1, nodes.size()):
		rest.append(i)
	helper.assign_owner(graph, def, rest)
	helper.assign_owner(graph, atk, [0])
	return [helper, graph, atk, nodes]


func _line(n: int) -> Array:
	var pairs: Array = []
	for i in n - 1:
		pairs.append([i, i + 1])
	return _setup(pairs)


func _combat(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n)


func _charge(n: SkillNode) -> int:
	return _combat(n).charge()


## [param n] holding T + [param excess] Charge: Shocked at level 1 for a small excess.
func _shock(n: SkillNode, excess := 1) -> void:
	var c := _combat(n)
	assert_gt(c.terrain_threshold(), 0, "fixture: %s has a T" % n.name)
	c.add_terrain(_light, c.terrain_threshold() + excess - c.charge())


func _cast(c: Array, target: SkillNode, hops: int, spread := true) -> AttackOutcome:
	var helper: SpellTestHelper = c[0]
	var config := helper.make_config(helper.fan_all() if spread else null, helper.owner_enemy(),
			helper.max_reducer(), {max_hops = hops})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n: Array[SkillNode] = c[3]
	return SpellResolver.resolve_against(spell, target, n[0], c[2], c[1], CombatWorld.live())


func _reached(c: Array, outcome: AttackOutcome) -> Array:
	var helper: SpellTestHelper = c[0]
	var by := helper.hits_by_node(outcome)
	var n: Array[SkillNode] = c[3]
	var out: Array = []
	for i in n.size():
		if by.has(n[i]):
			out.append(i)
	return out


# --- acceptance 4 ---------------------------------------------------------------

func test_a_walk_reaches_further_by_exactly_the_shocked_count() -> void:
	_no_arc()
	var plain := _line(6)
	assert_eq(_reached(plain, _cast(plain, plain[3][1], 1)), [1, 2], "a one-hop walk: A and B")
	CombatWorld.reset_live()
	var c := _line(6)
	var n: Array[SkillNode] = c[3]
	_shock(n[2])
	_shock(n[3])
	assert_eq(_reached(c, _cast(c, n[1], 1)), [1, 2, 3, 4],
			"B and C Shocked: two pass-throughs, two nodes further")


func test_each_pass_through_spends_the_conduct_cost() -> void:
	_no_arc()
	for band in _light.bands:
		band.conduct_cost = 2
	var c := _line(6)
	var n: Array[SkillNode] = c[3]
	_shock(n[2], 3)
	_shock(n[3], 3)
	var b := _charge(n[2])
	var cc := _charge(n[3])
	var d := _charge(n[4])
	_cast(c, n[1], 1)
	assert_eq(_charge(n[2]), b - _shocked_cost(), "B paid the conduct cost")
	assert_eq(_charge(n[3]), cc - _shocked_cost(), "C paid the conduct cost")
	assert_eq(_charge(n[4]), d, "D, not Shocked, paid nothing")


func test_a_walk_on_a_shocked_node_with_no_hops_left_still_leaves() -> void:
	_no_arc()
	var c := _line(4)
	var n: Array[SkillNode] = c[3]
	_shock(n[1])
	var a := _charge(n[1])
	assert_eq(_reached(c, _cast(c, n[1], 0)), [1, 2], "a zero-hop cast conducts on from A")
	assert_eq(_charge(n[1]), a - _shocked_cost(), "for the conduct cost")


func test_a_ring_of_shocked_nodes_terminates_on_the_visit_cap() -> void:
	_no_arc()
	var c := _setup([[0, 1], [1, 2], [2, 3], [3, 4], [4, 1]])
	var n: Array[SkillNode] = c[3]
	for i in range(1, 5):
		_shock(n[i], 6)
	var outcome := _cast(c, n[1], 0)
	assert_eq(_reached(c, outcome), [1, 2, 3, 4], "the walk goes round once")
	var helper: SpellTestHelper = c[0]
	var by := helper.hits_by_node(outcome)
	for i in range(1, 5):
		assert_eq((by[n[i]] as Array).size(), 1, "node %d struck once: the cap ends the ring" % i)


func test_a_spread_less_spell_spends_nothing() -> void:
	_no_arc()
	var c := _line(4)
	var n: Array[SkillNode] = c[3]
	_shock(n[1])
	var a := _charge(n[1])
	assert_eq(_reached(c, _cast(c, n[1], 0, false)), [1], "no spread, no walk")
	assert_eq(_charge(n[1]), a, "and no conduct cost")


# --- acceptance 5 ---------------------------------------------------------------

func test_conduction_and_the_arc_fire_on_one_arrival_and_their_spends_sum() -> void:
	var c := _line(4)
	var n: Array[SkillNode] = c[3]
	_shock(n[1], 2)
	var a := _charge(n[1])
	var outcome := _cast(c, n[1], 0)
	# The arc reaches 0 and 2 (two stacks spent); conduction pays its own cost.
	assert_eq(_charge(n[1]), a - 2 - _shocked_cost(), "the arc's spend and the conduct cost, summed")
	assert_true(_reached(c, outcome).has(2), "and the walk conducted on")
