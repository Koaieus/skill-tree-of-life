extends GutTest

## RandomWalkPropagation: picks one neighbour at random per step. Threaded
## through CastSpell.rng so a seeded RandomNumberGenerator gives a fully
## reproducible walk — the test fixture for any stochastic propagation.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func test_walk_length_equals_max_hops_plus_seed() -> void:
	var helper := H.new()
	# Line of 5: 0-1-2-3-4. Seed at 0. With max_hops=3 and any RNG the walk
	# strictly proceeds along the line (no choices to make until later nodes)
	# and produces seed + 3 hops = 4 hits.
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3, 4])
	var prop := RandomWalkPropagation.new()
	prop.max_hops = 3
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph, rng)
	assert_eq(outcome.hits.size(), 4)


func test_seeded_rng_is_reproducible() -> void:
	var helper := H.new()
	# Star at 0 with 5 spokes — multiple legal first-steps means the RNG's
	# choice is visible in the outcome. Same seed → same walk.
	var graph := helper.make_graph([[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3, 4, 5])
	var prop := RandomWalkPropagation.new()
	prop.max_hops = 1
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 1337
	var out_a := SpellResolver.resolve(spell, n[0], n[0], atk, graph, rng_a)

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 1337
	var out_b := SpellResolver.resolve(spell, n[0], n[0], atk, graph, rng_b)

	# Same seed → same chosen neighbour.
	assert_eq(out_a.hits.size(), out_b.hits.size())
	# Last hit is the random pick.
	assert_eq(out_a.hits[-1].target, out_b.hits[-1].target,
			"seeded RNG → identical walk")


func test_walk_terminates_when_no_unvisited_neighbours() -> void:
	var helper := H.new()
	# Tiny line: 0-1. From 0 walks to 1; from 1 the only neighbour (0) is
	# visited, so the walk stops one hop short of max_hops=5.
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1])
	var prop := RandomWalkPropagation.new()
	prop.max_hops = 5
	prop.revisit_visited = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph, rng)
	assert_eq(outcome.hits.size(), 2, "seed + one hop, then dead-end")


func test_friends_and_foes_both_eligible() -> void:
	var helper := H.new()
	# Seed at 0 (atk's node). All neighbours owned by atk. With max_hops=1
	# and no only_enemy filter on RandomWalkPropagation, the walk should
	# still produce a friendly hit.
	var graph := helper.make_graph([[0, 1], [0, 2]], self)
	var atk := helper.make_entity(graph, "A")
	helper.give_big_hp(atk)
	helper.assign_owner(graph, atk, [0, 1, 2])
	var prop := RandomWalkPropagation.new()
	prop.max_hops = 1
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph, rng)
	assert_eq(outcome.hits.size(), 2, "friendly fire — hit landed on caster's own node")
