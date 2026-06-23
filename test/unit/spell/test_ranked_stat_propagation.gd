extends GutTest

## RankedStatPropagation: picks the K highest- (or lowest-) ranked neighbours
## by a configurable stat_id. Reads each candidate via LocalStat so addon /
## entity bins compose like everywhere else.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func _set_node_health_base(node: SkillNode, hp: float) -> void:
	# Localized override — works regardless of the entity's node_health base.
	node.get_local_stat(&"node_health").base_value = hp


func test_highest_node_health_picks_fattest_neighbour() -> void:
	var helper := H.new()
	# Seed 0 has 3 enemy neighbours (1, 2, 3) with health 5/20/10 — top pick = 2.
	var graph := helper.make_graph([[0, 1], [0, 2], [0, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3])
	var n := graph.get_skill_nodes()
	_set_node_health_base(n[1], 5.0)
	_set_node_health_base(n[2], 20.0)
	_set_node_health_base(n[3], 10.0)
	var prop := RankedStatPropagation.new()
	prop.direction = RankedStatPropagation.Direction.HIGHEST
	prop.take_count = 1
	prop.max_hops = 1
	prop.only_enemy = false  # caster owns nothing here anyway
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	# Cast from one of n[2]'s own nodes? No — caster has no nodes. Pick n[0]
	# as the source for visual sanity; resolver doesn't filter on it.
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	# 2 hits: seed n[0] and hop n[2] (the highest-HP neighbour).
	assert_eq(outcome.hits.size(), 2)
	var by_node := helper.hits_by_node(outcome)
	assert_true(by_node.has(n[2]), "n[2] (HP 20) was picked")
	assert_false(by_node.has(n[1]) or by_node.has(n[3]))


func test_lowest_node_health_picks_weakest_neighbour() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [0, 2], [0, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3])
	var n := graph.get_skill_nodes()
	_set_node_health_base(n[1], 50.0)
	_set_node_health_base(n[2], 3.0)
	_set_node_health_base(n[3], 12.0)
	var prop := RankedStatPropagation.new()
	prop.direction = RankedStatPropagation.Direction.LOWEST
	prop.take_count = 1
	prop.max_hops = 1
	prop.only_enemy = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_true(by_node.has(n[2]), "n[2] (HP 3) was picked")


func test_take_count_picks_multiple() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [0, 2], [0, 3], [0, 4]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3, 4])
	var n := graph.get_skill_nodes()
	_set_node_health_base(n[1], 1.0)
	_set_node_health_base(n[2], 100.0)
	_set_node_health_base(n[3], 50.0)
	_set_node_health_base(n[4], 25.0)
	var prop := RankedStatPropagation.new()
	prop.direction = RankedStatPropagation.Direction.HIGHEST
	prop.take_count = 2
	prop.max_hops = 1
	prop.only_enemy = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	# Seed + top-2 = 3 hits; the top-2 are n[2] (100) and n[3] (50).
	assert_eq(outcome.hits.size(), 3)
	assert_true(by_node.has(n[2]) and by_node.has(n[3]))
	assert_false(by_node.has(n[1]) or by_node.has(n[4]))


func test_only_enemy_filter_excludes_caster_nodes_from_ranking() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [0, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.give_big_hp(atk)
	helper.assign_owner(graph, def, [0, 2])
	helper.assign_owner(graph, atk, [1])
	var n := graph.get_skill_nodes()
	# n[1] (atk) has wildly higher HP; without only_enemy it'd win the ranking.
	_set_node_health_base(n[1], 999.0)
	_set_node_health_base(n[2], 10.0)
	var prop := RankedStatPropagation.new()
	prop.direction = RankedStatPropagation.Direction.HIGHEST
	prop.take_count = 1
	prop.max_hops = 1
	prop.only_enemy = true
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_true(by_node.has(n[2]), "n[2] picked despite lower HP — friendly excluded")
	assert_false(by_node.has(n[1]))
