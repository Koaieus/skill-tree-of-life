extends GutTest

## Coverage for the wave-based propagation pipeline: FanAllStep + filter
## chains + merger semantics + max_visits_per_node enforcement + cancel
## telemetry + self-loop convergence (the Resonator setup).

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func _line_of(n: int) -> Array:
	var out: Array = []
	for i in n - 1:
		out.append([i, i + 1])
	return out


func _setup_full_enemy(adjacency: Array, attacker_indices: Array,
		defender_indices: Array) -> Array:
	# Returns [helper, graph, attacker, defender]
	var helper := H.new()
	var graph := helper.make_graph(adjacency, self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.give_big_hp(atk)
	helper.assign_owner(graph, def, defender_indices)
	helper.assign_owner(graph, atk, attacker_indices)
	return [helper, graph, atk, def]


# ── Fan-all baseline ───────────────────────────────────────────────────────


func test_max_hops_zero_yields_seed_only() -> void:
	var ctx := _setup_full_enemy([[0, 1], [1, 2]], [0], [1, 2])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 1)


func test_one_hop_fans_to_all_enemy_neighbours() -> void:
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3]], [0], [1, 2, 3])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_eq(outcome.hits.size(), 3)
	assert_true(by_node.has(n[1]) and by_node.has(n[2]) and by_node.has(n[3]))


func test_only_enemy_filter_excludes_caster_nodes() -> void:
	var ctx := _setup_full_enemy([[0, 1], [1, 2]], [0, 2], [1])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Only the seed lands — both neighbours are caster-owned.
	assert_eq(outcome.hits.size(), 1)
	assert_eq(outcome.hits[0].target, n[1])


func test_damage_falls_off_per_hop() -> void:
	var ctx := _setup_full_enemy(_line_of(4), [0], [1, 2, 3])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 2, damage_multiplier_per_hop = 0.5})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), 10.0, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[2]), 5.0, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[3]), 2.5, 0.001)


# ── Merger semantics — the headline change ────────────────────────────────


func test_diamond_sum_reducer_adds_converging_branches() -> void:
	# Diamond: 1 → {2, 3} → 4. Two shoulders → node 4 gets one merged hit.
	# SUM reducer: damages add.
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.sum_reducer(),
			{max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	# Node 4 hit ONCE (merged), with summed damage 10 + 10 = 20.
	assert_eq((by_node[n[4]] as Array).size(), 1, "node 4 merged into one hit")
	assert_almost_eq(helper.total_damage_on(outcome, n[4]), 20.0, 0.001)


func test_diamond_max_reducer_takes_strongest_only() -> void:
	# Same diamond — but MaxDamageReducer keeps just the strongest incident.
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_eq((by_node[n[4]] as Array).size(), 1, "node 4 single merged hit")
	# Both shoulders arrived with equal damage; max == that damage (10).
	assert_almost_eq(helper.total_damage_on(outcome, n[4]), 10.0, 0.001)


func test_cancel_if_multi_fizzles_overlapping_node() -> void:
	# Same diamond — CancelIfMulti returns null on the 2-incident D, so
	# node 4 gets ZERO hits and a cancellation entry appears.
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.cancel_if_multi(),
			{max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_false(by_node.has(n[4]), "node 4 received nothing — fizzled")
	assert_eq(outcome.cancellations.size(), 1, "one cancellation recorded")
	assert_eq(outcome.cancellations[0].node, n[4])
	assert_eq(outcome.cancellations[0].incident_count, 2)


# ── Visit-cap enforcement ──────────────────────────────────────────────────


func test_default_visit_cap_blocks_node_revisits() -> void:
	# Cycle 0-1-2-3-0; even with high hops, max_visits=1 means each
	# node hit at most once.
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [2, 3], [3, 0]], [], [0, 1, 2, 3])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 10, max_visits_per_node = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 4, "each of 4 nodes hit exactly once")


func test_max_visits_cap_allows_bounded_revisits() -> void:
	# Cycle 0-1-2-3-0, max_visits=2. Each node can be hit twice over the cast.
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [2, 3], [3, 0]], [], [0, 1, 2, 3])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.sum_reducer(),
			{max_hops = 5, max_visits_per_node = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[0], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	# Every node should be hit ≤2 times (cap), and ≥1 (reachable).
	for node in by_node:
		var count := (by_node[node] as Array).size()
		assert_true(count >= 1 and count <= 2,
				"node %s hit %d times (must be 1..2)" % [node, count])


# ── Self-loop convergence (the Resonator reason-for-being) ────────────────


func test_self_loop_sum_merger_compounds_returns() -> void:
	# 0(atk) - 1, plus 1 has a self-loop. With FanAllStep + SUM + revisits,
	# the self-loop's two returns at node 1 merge into one doubled hit on
	# the next wave.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 1]], self)  # 1→1 self-loop
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.sum_reducer(),
			{max_hops = 1, max_visits_per_node = 2, damage_multiplier_per_hop = 1.0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Wave 0: seed at node 1 (10 dmg).
	# Wave 1: node 1 fans to neighbours of itself — self-loop means {1, 1}.
	# SUM merger collapses to one 20-dmg hit at node 1.
	# Total: hit at wave 0 (10) + merged hit at wave 1 (20) = 30 across two hits.
	var hits_on_1: Array = helper.hits_by_node(outcome).get(n[1], [])
	assert_eq(hits_on_1.size(), 2, "node 1 hit twice (seed + merged self-loop return)")
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), 30.0, 0.001)


# ── Filter dispatch ────────────────────────────────────────────────────────


func test_degree_filter_strict_less_routes_downhill() -> void:
	# Hub 1 (deg 3) - leaves 2, 3, 4. Seed at hub, fan with DegreeFilter(LESS)
	# → propagates only to the lower-degree neighbours (all leaves).
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3], [1, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var filter := helper.composite_filter([helper.owner_enemy(), helper.degree_filter()])
	var config := helper.make_config(helper.fan_all(), filter, helper.max_reducer(), {max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Seed + 3 leaves = 4 hits.
	assert_eq(outcome.hits.size(), 4)


# ── Edge case ──────────────────────────────────────────────────────────────


func test_disconnected_island_unreachable() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var orphan_scene := preload("res://skill_node/skill_node.tscn")
	var orphan := orphan_scene.instantiate() as SkillNode
	orphan.name = "Orphan"
	graph.skill_nodes_container.add_child(orphan)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 99})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	for hit in outcome.hits:
		assert_ne(hit.target, n[3], "orphan node never reached")
