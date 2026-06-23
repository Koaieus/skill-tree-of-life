extends GutTest

## NoPropagation: single-target. next_hops always empty regardless of graph
## state. Through the resolver, that means exactly one hit (the seed) and
## the damage equals base_damage * seed_damage_fraction.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func _make_h() -> SpellTestHelper:
	return H.new()


func test_next_hops_is_always_empty() -> void:
	var helper := _make_h()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.assign_owner(graph, def, [1, 2])
	var prop := NoPropagation.new()
	prop.max_hops = 5  # irrelevant: NoPropagation never produces a next hop
	var state := CastSpell.new()
	state.graph = graph
	state.current_node = graph.get_skill_nodes()[1]
	state.caster = atk
	assert_eq(prop.next_hops(state).size(), 0)


func test_resolver_produces_single_seed_hit() -> void:
	var helper := _make_h()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var spell := helper.make_spell(NoPropagation.new(), [DamageEffect.new()], 10.0)
	var nodes := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, nodes[2], nodes[0], atk, graph)
	assert_eq(outcome.hits.size(), 1, "single-target spell produces exactly one hit")
	assert_eq(outcome.hits[0].target, nodes[2], "seed is the only target")
	assert_almost_eq(outcome.hits[0].amount, 10.0, 0.001)


func test_seed_damage_fraction_scales_seed_only() -> void:
	var helper := _make_h()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	var prop := NoPropagation.new()
	prop.seed_damage_fraction = 0.25
	var spell := helper.make_spell(prop, [DamageEffect.new()], 40.0)
	var nodes := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, nodes[1], nodes[0], atk, graph)
	assert_eq(outcome.hits.size(), 1)
	assert_almost_eq(outcome.hits[0].amount, 10.0, 0.001)
