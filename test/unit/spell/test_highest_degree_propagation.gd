extends GutTest

## HighestDegreePropagation: pick the K most-connected neighbours. Degree
## is graph-live (Graph.get_neighbours().size()), so adding/removing edges
## between casts changes the answer.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func test_picks_neighbour_with_highest_degree() -> void:
	var helper := H.new()
	# 0 (seed) - {1, 2, 3}. Make 2 a hub: also connect 2 to 4, 5, 6.
	# Degrees among the seed's neighbours: 1→1, 2→4 (to 0,4,5,6), 3→1.
	var graph := helper.make_graph([[0, 1], [0, 2], [0, 3], [2, 4], [2, 5], [2, 6]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3, 4, 5, 6])
	var prop := HighestDegreePropagation.new()
	prop.take_count = 1
	prop.max_hops = 1
	prop.only_enemy = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_true(by_node.has(n[2]), "n[2] (degree 4) wins")
	assert_false(by_node.has(n[1]) or by_node.has(n[3]))


func test_take_count_picks_top_k_hubs() -> void:
	var helper := H.new()
	# 0's neighbours 1/2/3 have degrees 3/4/2.
	var graph := helper.make_graph([
		[0, 1], [0, 2], [0, 3],
		[1, 4], [1, 5],          # 1 → degree 3 (0,4,5)
		[2, 6], [2, 7], [2, 8],  # 2 → degree 4 (0,6,7,8)
		[3, 9],                  # 3 → degree 2 (0,9)
	], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	var prop := HighestDegreePropagation.new()
	prop.take_count = 2
	prop.max_hops = 1
	prop.only_enemy = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_true(by_node.has(n[2]) and by_node.has(n[1]))
	assert_false(by_node.has(n[3]))


func test_only_enemy_filters_caster_hubs() -> void:
	var helper := H.new()
	# 0(seed)'s neighbours: 1 owned by atk (high degree), 2 owned by def (low degree).
	var graph := helper.make_graph([
		[0, 1], [0, 2],
		[1, 3], [1, 4], [1, 5],  # atk's hub
	], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.give_big_hp(atk)
	helper.assign_owner(graph, def, [0, 2])
	helper.assign_owner(graph, atk, [1, 3, 4, 5])
	var prop := HighestDegreePropagation.new()
	prop.take_count = 1
	prop.max_hops = 1
	prop.only_enemy = true
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_true(by_node.has(n[2]), "n[2] picked — n[1] filtered out as caster's")
	assert_false(by_node.has(n[1]))
