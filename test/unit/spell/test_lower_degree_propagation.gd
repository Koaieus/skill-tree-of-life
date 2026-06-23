extends GutTest

## LowerDegreePropagation (Leafblaster): only propagates to neighbours with
## strictly lower (or ≤) degree than the current node. Drains outward from
## hubs toward leaves; ridges at equal degree stop the walk unless
## strict_less_than is off.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func test_strict_less_than_descends_to_leaves_only() -> void:
	var helper := H.new()
	# Hub 0 (deg 4: 1,2,3,4) → leaves 1/2/3/4 (each deg 1). Seeded at 0 should
	# splash to all four; from any leaf there's nowhere to go (degree 1 is
	# the floor) so the walk terminates.
	var graph := helper.make_graph([[0, 1], [0, 2], [0, 3], [0, 4]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3, 4])
	var prop := LowerDegreePropagation.new()
	prop.max_hops = 3
	prop.strict_less_than = true
	prop.only_enemy = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	# Seed + 4 leaves = 5 hits.
	assert_eq(outcome.hits.size(), 5)


func test_strict_less_than_blocks_equal_degree_ridge() -> void:
	var helper := H.new()
	# A 4-cycle: every node has degree 2. With strict_less_than=true,
	# nothing past the seed propagates.
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 0]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3])
	var prop := LowerDegreePropagation.new()
	prop.max_hops = 5
	prop.strict_less_than = true
	prop.only_enemy = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 1, "ridge of equal degree stops the walk")


func test_lte_mode_rides_equal_degree_ridge() -> void:
	var helper := H.new()
	# Same 4-cycle, but with strict_less_than off: ≤ is allowed so the spell
	# rides the ring. visited dedup keeps it from looping back over itself.
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 0]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [0, 1, 2, 3])
	var prop := LowerDegreePropagation.new()
	prop.max_hops = 5
	prop.strict_less_than = false
	prop.only_enemy = false
	var spell := helper.make_spell(prop, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	# All 4 nodes get hit at least once. Branches fork around the ring;
	# total hit count > 4 is acceptable (BFS branches each carry visited).
	var by_node := helper.hits_by_node(outcome)
	assert_eq(by_node.size(), 4, "all four ring nodes touched")
