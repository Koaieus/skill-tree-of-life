extends GutTest

## Miasma (#1503): the poison cloud. Wide and thin — every enemy node in the
## fan takes the spell's folded innate poison once per visit, capped by the
## def's own `max_visits_per_node`; two branches converging don't stack.

const _MIASMA: SpellDef = preload("res://attack/spell/defs/miasma.tres")

var _h: SpellTestHelper


func before_each() -> void:
	_h = SpellTestHelper.new()


func _cast(adjacency: Array, enemy: Array) -> Array:
	var graph := _h.make_graph(adjacency, self)
	var atk := _h.make_entity(graph, "A", Color.RED)
	var def := _h.make_entity(graph, "D", Color.BLUE)
	_h.give_big_hp(def)
	_h.assign_owner(graph, atk, [0])
	_h.assign_owner(graph, def, enemy)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_MIASMA, n[enemy[0]], n[0], atk, graph)
	return [n, outcome]


func _statuses_on(outcome: AttackOutcome, node: SkillNode) -> Array:
	var out: Array = []
	for hit in outcome.hits:
		if hit.target == node and hit is StatusInstance:
			out.append(hit)
	return out


func test_ring_lands_innate_once_per_visit_capped_by_the_knob() -> void:
	var r := _cast([[0, 1], [1, 2], [2, 3], [3, 4], [4, 1]], [1, 2, 3, 4])
	var n: Array = r[0]
	var innate: int = _MIASMA.affinities[0].innate
	var cap: int = _MIASMA.propagation.max_visits_per_node
	for i in [1, 2, 3, 4]:
		var hits := _statuses_on(r[1], n[i])
		assert_gt(hits.size(), 0, "ring node %d is poisoned" % i)
		assert_lte(hits.size(), cap, "node %d lands at most max_visits times" % i)
		for hit in hits:
			assert_eq(hit.power, float(innate), "each landing is the folded innate")


func test_diamond_far_node_does_not_stack_two_branches_in_one_wave() -> void:
	# Two branches converge on node 3 in the same wave: one merged landing at
	# the innate, never 2x. (Its later landings are the second visit's bounce,
	# bounded by max_visits and on a later wave.)
	var r := _cast([[0, 1], [0, 2], [1, 3], [2, 3]], [1, 2, 3])
	var n: Array = r[0]
	var far := _statuses_on(r[1], n[3])
	var cap: int = _MIASMA.propagation.max_visits_per_node
	assert_gt(far.size(), 0)
	assert_lte(far.size(), cap, "bounded by the visits knob")
	var times := {}
	for hit in far:
		assert_eq(hit.power, float(_MIASMA.affinities[0].innate), "default fold: no stacking")
		assert_false(times.has(hit.arrival_time), "one landing per wave, branches merged")
		times[hit.arrival_time] = true
