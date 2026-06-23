extends GutTest

## AllNeighboursPropagation: BFS fan-out per hop. Drives Lightning, Crunch,
## Flood. The state-per-branch model means a node reachable via multiple
## independent BFS branches CAN be hit multiple times (each branch carries
## its own `visited`); the visited check only prevents a branch from
## re-entering its own path.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func _line_of(n: int) -> Array:
	var out: Array = []
	for i in n - 1:
		out.append([i, i + 1])
	return out


func test_seed_only_when_max_hops_is_zero() -> void:
	var helper := H.new()
	var graph := helper.make_graph(_line_of(4), self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var prop := AllNeighboursPropagation.new()
	prop.max_hops = 0
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 1, "max_hops=0 → seed only")


func test_line_one_hop_hits_both_neighbours() -> void:
	var helper := H.new()
	# 0 (caster) - 1 (seed) - 2 (right) , with 1 also adjacent to 3 below
	# layout: square-ish so seed 1 has two enemy neighbours (2, 3).
	var graph := helper.make_graph([[0, 1], [1, 2], [1, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var prop := AllNeighboursPropagation.new()
	prop.max_hops = 1
	prop.damage_multiplier_per_hop = 1.0
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Hits: seed n[1], plus n[2] and n[3]. (n[0] is the caster's node → filtered.)
	var by_node := helper.hits_by_node(outcome)
	assert_eq(outcome.hits.size(), 3)
	assert_true(by_node.has(n[1]) and by_node.has(n[2]) and by_node.has(n[3]))


func test_only_enemy_false_includes_caster_nodes() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.give_big_hp(atk)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0, 2])
	var prop := AllNeighboursPropagation.new()
	prop.max_hops = 1
	prop.only_enemy = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Seed n[1] + both neighbours (n[0] and n[2]) — friendly fire on.
	assert_eq(outcome.hits.size(), 3)


func test_only_enemy_true_filters_caster_nodes() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0, 2])
	var prop := AllNeighboursPropagation.new()
	prop.max_hops = 1
	prop.only_enemy = true
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Only the seed lands — both neighbours are caster-owned.
	assert_eq(outcome.hits.size(), 1)
	assert_eq(outcome.hits[0].target, n[1])


func test_damage_falls_off_per_hop() -> void:
	var helper := H.new()
	# Line: 0(atk) - 1 - 2 - 3, seed at 1, max_hops=2.
	var graph := helper.make_graph(_line_of(4), self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var prop := AllNeighboursPropagation.new()
	prop.max_hops = 2
	prop.damage_multiplier_per_hop = 0.5
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Seed 10 at n[1], 5 at n[2] (one hop), 2.5 at n[3] (two hops).
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), 10.0, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[2]), 5.0, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[3]), 2.5, 0.001)


func test_diamond_double_hits_via_parallel_branches() -> void:
	# 0(atk) seeds at 1; 1 fans to 2 and 3; both fan to 4. Each branch has
	# its own `visited`, so node 4 is hit TWICE — once via each shoulder.
	# This is the documented model (per-branch visited, not global), and
	# captures it so a refactor toward global dedup is a deliberate break.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3, 4])
	helper.assign_owner(graph, atk, [0])
	var prop := AllNeighboursPropagation.new()
	prop.max_hops = 2
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_eq((by_node[n[4]] as Array).size(), 2, "node 4 hit once per BFS branch")


func test_disconnected_island_unreachable() -> void:
	var helper := H.new()
	# 0 - 1 - 2 ;  3 isolated (no edges)
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	# Manually add an extra orphan node by instantiating one — make_graph
	# infers node count from adjacency, so we expand it the explicit way.
	var orphan_scene := preload("res://skill_node/skill_node.tscn")
	var orphan := orphan_scene.instantiate() as SkillNode
	orphan.name = "Orphan"
	graph.skill_nodes_container.add_child(orphan)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var prop := AllNeighboursPropagation.new()
	prop.max_hops = 99
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	for hit in outcome.hits:
		assert_ne(hit.target, n[3], "orphan node never reached")
