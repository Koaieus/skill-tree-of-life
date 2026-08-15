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
			{max_hops = 2, hop_damage = helper.multiply_progression(0.5)})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Seed = spell_damage(cast-from node) × power; the falloff is a ratio of it.
	var seed_dmg: float = helper.seed_multiplier(n[0]) * spell.power
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), seed_dmg, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[2]), seed_dmg * 0.5, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[3]), seed_dmg * 0.25, 0.001)


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
	# Node 4 hit ONCE (merged), with summed damage seed + seed.
	var seed_dmg: float = helper.seed_multiplier(n[0]) * spell.power
	assert_eq((by_node[n[4]] as Array).size(), 1, "node 4 merged into one hit")
	assert_almost_eq(helper.total_damage_on(outcome, n[4]), seed_dmg * 2.0, 0.001)


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
	# Both shoulders arrived with equal damage; max == that damage (the seed).
	var seed_dmg: float = helper.seed_multiplier(n[0]) * spell.power
	assert_almost_eq(helper.total_damage_on(outcome, n[4]), seed_dmg, 0.001)


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
			{max_hops = 1, max_visits_per_node = 2, hop_damage = helper.multiply_progression(1.0)})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	# Wave 0: the seed lands at node 1.
	# Wave 1: node 1 fans to neighbours of itself — self-loop means {1, 1}.
	# SUM merger collapses to one 2×seed hit at node 1.
	# Total: wave 0 (seed) + merged wave 1 (2×seed) = 3×seed across two hits.
	var seed_dmg: float = helper.seed_multiplier(n[0]) * spell.power
	var hits_on_1: Array = helper.hits_by_node(outcome).get(n[1], [])
	assert_eq(hits_on_1.size(), 2, "node 1 hit twice (seed + merged self-loop return)")
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), seed_dmg * 3.0, 0.001)
	# The wave-1 return arrives via the self-loop edge (target == predecessor),
	# so the resolver stamps it SELF_LOOP — the one verb branch geometry can't
	# recover (origin == target). Locks the a/b/e/d vocabulary's `e` case.
	var self_loops: Array[PropagationEvent] = []
	for ev in outcome.timeline:
		if ev.verb == PropagationEvent.Verb.SELF_LOOP:
			self_loops.append(ev)
	assert_eq(self_loops.size(), 1, "wave-1 return stamped SELF_LOOP")
	assert_eq(self_loops[0].target, n[1], "self-loop lands back on node 1")


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


# ── First-wins reducer ──────────────────────────────────────────────────────


func test_first_reducer_keeps_earliest_arrival_on_convergence() -> void:
	# Same diamond as the sum/max/cancel trio above — FirstReducer keeps
	# whichever branch arrived first (node 2, edges declared before node 3's)
	# and silently drops node 3's incident, unlike sum (adds) or max (picks
	# the stronger).
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.first_reducer(),
			{max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_eq((by_node[n[4]] as Array).size(), 1, "node 4 single merged hit")
	var landing_at_4: PropagationEvent = null
	for ev in outcome.timeline:
		if ev.target == n[4] and ev.verb != PropagationEvent.Verb.CANCEL:
			landing_at_4 = ev
	assert_not_null(landing_at_4, "node 4 has a landing event")
	assert_eq(landing_at_4.predecessor, n[2],
			"first-arrived branch (via node 2) wins; node 3's incident is dropped")


# ── Custom expression reducer ───────────────────────────────────────────────


func test_expression_reducer_evaluates_custom_formula() -> void:
	# Same diamond — a formula (avg × count) that's algebraically equal to
	# sum only at the point of convergence, and identity everywhere a group
	# is a singleton (the resolver calls the reducer on EVERY node, not just
	# where branches meet — a formula that isn't identity-for-one, like a
	# flat `sum_damage * 0.75`, would keep scaling down node 2 and node 3's
	# solo landings too, and the closed form stops being seed_dmg × 2).
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(),
			helper.expression_reducer("avg_damage * incident_count"), {max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var seed_dmg: float = helper.seed_multiplier(n[0]) * spell.power
	assert_almost_eq(helper.total_damage_on(outcome, n[4]), seed_dmg * 2.0, 0.001)


func test_expression_reducer_negative_result_cancels() -> void:
	# Same diamond — an expression that's identity for a solo landing (so
	# node 2/3's own hits still land) but resolves negative specifically at
	# a 2-incident convergence, CANCELling just node 4, same contract as a
	# stock reducer returning null.
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(),
			helper.expression_reducer("sum_damage - (incident_count - 1) * 999999.0"), {max_hops = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var by_node := helper.hits_by_node(outcome)
	assert_true(by_node.has(n[1]) and by_node.has(n[2]) and by_node.has(n[3]),
			"solo landings pass through unscathed")
	assert_false(by_node.has(n[4]), "node 4 received nothing — cancelled on convergence")
	assert_eq(outcome.cancellations.size(), 1, "one cancellation recorded")
	assert_eq(outcome.cancellations[0].node, n[4])


# ── Distance-to-core filter ─────────────────────────────────────────────────


func test_core_distance_filter_admits_closer_rejects_farther() -> void:
	var helper := H.new()
	var graph := helper.make_graph(_line_of(5), self)  # line of 5: 0-1-2-3-4
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	var n := graph.get_skill_nodes()
	helper.assign_owner(graph, def, [4])
	def.core_location = n[0]
	var propagation_ctx := PropagationContext.new()
	propagation_ctx.graph = graph
	propagation_ctx.caster = atk
	propagation_ctx.seed_node = n[4]  # owned by def, non-caster → its core is the target
	var filter := helper.core_distance_filter()
	assert_true(filter.allows(n[3], n[2], null, propagation_ctx),
			"node 2 is closer to the core (n0) than node 3")
	assert_false(filter.allows(n[3], n[4], null, propagation_ctx),
			"node 4 is farther from the core (n0) than node 3")


# ── Seeded random pick ───────────────────────────────────────────────────────


func test_random_pick_step_seeded_picks_one_deterministically() -> void:
	var ctx := _setup_full_enemy([[0, 1], [1, 2], [1, 3], [1, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	var config := helper.make_config(helper.random_pick_step(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var outcome1 := SpellResolver.resolve(spell, n[1], n[0], atk, graph, rng1)
	# Seed hit + exactly one randomly-picked neighbour — never all three.
	assert_eq(outcome1.hits.size(), 2, "seed hit + exactly one random pick")
	var picked := outcome1.hits[1].target
	assert_true(picked in [n[2], n[3], n[4]], "picked one of the three eligible neighbours")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var outcome2 := SpellResolver.resolve(spell, n[1], n[0], atk, graph, rng2)
	assert_eq(outcome2.hits[1].target, picked, "same seed reproduces the same pick")


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
