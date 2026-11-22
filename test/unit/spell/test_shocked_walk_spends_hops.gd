extends GutTest

## A spell walk spends a hop on a Shocked node like anywhere else: the node's
## arc is Lightning's only line-maker, so the walk's reach (its timeline
## landings, counted apart from the arc copies' hits) is the hop budget alone,
## and passing through pays only the arc's own spend.
##
## Board: a line (or a ring), node 0 the caster's, the rest the defender's.
## Resolved against the live world so the Charge ints read back after the cast.

const H := preload("res://test/unit/spell/spell_test_helper.gd")

var _light: Element = null
var _go_offs: Array = []


func before_each() -> void:
	CombatWorld.reset_live()
	# Held: an unheld roster reloads its defs and drops a swapped field.
	_light = ElementRoster.shared().by_id(&"lightning")
	_go_offs = []
	for band in _light.bands:
		_go_offs.append(band.go_off)


func after_each() -> void:
	for i in _light.bands.size():
		_light.bands[i].go_off = _go_offs[i]
	CombatWorld.reset_live()


## Lightning's bands with no arc: only the walk moves.
func _no_arc() -> void:
	for band in _light.bands:
		band.go_off = null


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


## Node indices the walk itself landed on (its timeline), arc copies apart.
func _walked(c: Array, outcome: AttackOutcome) -> Array:
	var n: Array[SkillNode] = c[3]
	var out: Array = []
	for ev: PropagationEvent in outcome.timeline:
		var i := n.find(ev.target)
		if i >= 0 and not out.has(i):
			out.append(i)
	out.sort()
	return out


## Node indices any hit of the cast landed on, the arcs' copies included.
func _struck(c: Array, outcome: AttackOutcome) -> Array:
	var helper: SpellTestHelper = c[0]
	var by := helper.hits_by_node(outcome)
	var n: Array[SkillNode] = c[3]
	var out: Array = []
	for i in n.size():
		if by.has(n[i]):
			out.append(i)
	return out


func _last_wave(outcome: AttackOutcome) -> int:
	var last := -1
	for ev: PropagationEvent in outcome.timeline:
		last = maxi(last, ev.beat)
	return last


# --- a: a Shocked line is walked as far as a plain one ---------------------------

func test_a_walk_down_a_shocked_line_reaches_as_far_as_down_a_plain_one() -> void:
	var plain := _line(6)
	var plain_n: Array[SkillNode] = plain[3]
	assert_eq(_walked(plain, _cast(plain, plain_n[1], 1)), [1, 2], "a one-hop walk: A and B")
	CombatWorld.reset_live()
	var c := _line(6)
	var n: Array[SkillNode] = c[3]
	_shock(n[2])
	_shock(n[3])
	var outcome := _cast(c, n[1], 1)
	assert_eq(_walked(c, outcome), [1, 2], "B and C Shocked: the walk still ends on its hop at B")
	assert_true(_struck(c, outcome).has(3), "while B's arc still carries the payload on to C")


# --- b: a 0-hop cast on a Shocked seed stays put; its arc still goes off ---------

func test_a_zero_hop_cast_on_a_shocked_seed_does_not_walk_on() -> void:
	var c := _line(4)
	var n: Array[SkillNode] = c[3]
	_shock(n[1], 2)
	var outcome := _cast(c, n[1], 0)
	assert_eq(_walked(c, outcome), [1], "no hop left: the walk is the seed alone")
	assert_true(_struck(c, outcome).has(2), "the seed's arc went off and its copy landed on B")


# --- c: passing through pays the arc's spend, nothing more -----------------------

func test_a_walk_through_a_shocked_node_pays_only_its_arc_spend() -> void:
	# Reference: a spread-less cast on B, so nothing walks through it; B's arc alone.
	var ref := _line(6)
	var ref_n: Array[SkillNode] = ref[3]
	_shock(ref_n[2], 3)
	var ref_before := _charge(ref_n[2])
	_cast(ref, ref_n[2], 0, false)
	var arc_spend := ref_before - _charge(ref_n[2])
	assert_gt(arc_spend, 0, "fixture: B's arc spent Charge")
	CombatWorld.reset_live()
	var c := _line(6)
	var n: Array[SkillNode] = c[3]
	_shock(n[2], 3)
	var before := _charge(n[2])
	var outcome := _cast(c, n[1], 2)
	assert_true(_walked(c, outcome).has(3), "fixture: the walk passed through B on to C")
	assert_eq(before - _charge(n[2]), arc_spend, "B paid its arc's spend, never a pass-through Charge")


# --- d: a ring of Shocked nodes ends on hops -------------------------------------

func test_a_ring_of_shocked_nodes_ends_on_hops() -> void:
	_no_arc()
	var c := _setup([[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [7, 8], [8, 1]])
	var n: Array[SkillNode] = c[3]
	for i in range(1, 9):
		_shock(n[i], 6)
	var outcome := _cast(c, n[1], 2)
	assert_eq(_last_wave(outcome), 2, "a two-hop walk ends after its second hop's wave")
	assert_eq(_walked(c, outcome), [1, 2, 3, 7, 8], "two nodes each way round the ring, no further")
