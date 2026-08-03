extends GutTest

## Crit conditions (SelfLoop / Leaf) and the full crit resolution path in
## SpellResolver (stat roll + condition OR). Tests cover:
##   * Condition predicates in isolation (no SpellResolver).
##   * Stat-path crits with seeded RNG for determinism.
##   * Condition-path crits via SpellDef.crit_conditions.
##   * Combined path: both stat and condition can fire (crit_tier 2).
##   * Multiplier application and DamageInstance markers.

const H := preload("res://test/unit/spell/spell_test_helper.gd")


# ── Condition predicates ─────────────────────────────────────────────────────

func test_self_loop_condition_null_target_returns_false() -> void:
	var c := SelfLoopCritCondition.new()
	assert_false(c.evaluate(null, null, null))


func test_self_loop_condition_no_self_loops_returns_false() -> void:
	# N0 connected to N1 (no self-loops in graph). Arriving at N0 via edge
	# from N1 → predecessor (N1) != target (N0) → no crit, regardless of
	# self-loop presence on the node (#353: predicate is "did we traverse a
	# self-loop edge to land here", not "does this node have a self-loop").
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var c := SelfLoopCritCondition.new()
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.predecessor = n[1]
	assert_false(c.evaluate(state, n[0], null))


func test_self_loop_condition_seed_landing_on_self_loop_node_returns_false() -> void:
	# N0 has a self-loop, but the seed landing has predecessor=null → no
	# crit. The first hit doesn't crit by design (#353).
	var helper := H.new()
	var graph := helper.make_graph([[0, 0]], self)  # self-loop on N0
	var c := SelfLoopCritCondition.new()
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.predecessor = null
	assert_false(c.evaluate(state, n[0], null), "seed (predecessor=null) never crits")


func test_self_loop_condition_target_via_self_loop_edge_returns_true() -> void:
	# N1 has a self-loop. Arriving at N1 with predecessor=N1 means the spell
	# just traversed the self-loop edge → crit.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 1]], self)
	var c := SelfLoopCritCondition.new()
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.predecessor = n[1]
	assert_true(c.evaluate(state, n[1], null), "self-loop traversal crits")


func test_self_loop_condition_edge_hop_into_self_loop_node_returns_false() -> void:
	# N1 has a self-loop, but the spell arrived via the N0→N1 edge (not the
	# self-loop). No crit — the predicate fires on the *traversal*, not the
	# node's static topology.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 1]], self)
	var c := SelfLoopCritCondition.new()
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.predecessor = n[0]
	assert_false(c.evaluate(state, n[1], null))


func test_leaf_condition_null_target_returns_false() -> void:
	var c := LeafCritCondition.new()
	assert_false(c.evaluate(null, null, null))


func test_leaf_condition_null_state_or_graph_returns_false() -> void:
	var c := LeafCritCondition.new()
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.graph = null
	assert_false(c.evaluate(state, n[0], null))
	state.graph = graph
	assert_false(c.evaluate(null, n[0], null))


func test_leaf_condition_non_leaf_returns_false() -> void:
	# N1 is degree 2 within its owner's territory (N0 and N2 are both owned).
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var def := helper.make_entity(graph, "D")
	helper.assign_owner(graph, def, [0, 1, 2])
	var c := LeafCritCondition.new()
	var state := CastSpell.new()
	state.graph = graph
	var n := graph.get_skill_nodes()
	assert_false(c.evaluate(state, n[1], null))


func test_leaf_condition_degree_1_returns_true() -> void:
	# N0 is degree 1 (only connected to N1)
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var def := helper.make_entity(graph, "D")
	helper.assign_owner(graph, def, [0, 1, 2])
	var c := LeafCritCondition.new()
	var state := CastSpell.new()
	state.graph = graph
	var n := graph.get_skill_nodes()
	assert_eq(graph.get_neighbours(n[0]).size(), 1)
	assert_true(c.evaluate(state, n[0], null))


## The leaf test is on the ENTITY-induced subgraph, not the whole graph: a node
## whose only other neighbour belongs to someone else dangles off its owner's
## territory and crits, even though its graph degree is 2.
func test_leaf_condition_reads_entity_degree_not_graph_degree() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.assign_owner(graph, atk, [0])
	helper.assign_owner(graph, def, [1, 2])
	var c := LeafCritCondition.new()
	var state := CastSpell.new()
	state.graph = graph
	var n := graph.get_skill_nodes()
	assert_eq(graph.get_neighbours(n[1]).size(), 2, "N1 graph degree is 2")
	assert_true(c.evaluate(state, n[1], null), "…but only 1 of those is D's → leaf")


# ── Stat-path crit via SpellResolver ───────────────────────────────────────

func test_stat_path_no_crit_when_chance_zero() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var config := helper.make_config(helper.no_step(), helper.owner_enemy(), null, {max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 1)
	assert_false(outcome.hits[0].is_crit, "no crit when chance is 0")
	assert_eq(outcome.timeline[0].crit_tier, 0)


func test_stat_path_crits_when_chance_one() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 1.0
	var config := helper.make_config(helper.no_step(), helper.owner_enemy(), null, {max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 1)
	assert_true(outcome.hits[0].is_crit, "crit when chance is 1.0")
	assert_eq(outcome.timeline[0].crit_tier, 1)


func test_stat_path_multiplies_damage_on_crit() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 1.0
	atk.stat_board.get_stat(&"crit_multiplier").base_value = 3.0
	var config := helper.make_config(helper.no_step(), helper.owner_enemy(), null, {max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 1)
	var hit := outcome.hits[0]
	assert_true(hit.is_crit)
	assert_eq(hit.crit_multiplier, 3.0)
	var seed_dmg: float = helper.seed_multiplier(n[0]) * spell.power
	assert_almost_eq(hit.amount, seed_dmg * 3.0, 0.001)


func test_stat_path_reproduces_crits_under_seed() -> void:
	# Crits are derived from the caller's seed without consuming the
	# propagation stream — same seed → same crit outcome every run.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.5
	var config := helper.make_config(helper.no_step(), helper.owner_enemy(), null, {max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var n := graph.get_skill_nodes()

	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var outcome1 := SpellResolver.resolve(spell, n[1], n[0], atk, graph, rng1)

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var outcome2 := SpellResolver.resolve(spell, n[1], n[0], atk, graph, rng2)

	assert_eq(outcome1.hits[0].is_crit, outcome2.hits[0].is_crit, "same seed → same crit flag")
	assert_eq(outcome1.timeline[0].crit_tier, outcome2.timeline[0].crit_tier, "same seed → same crit_tier")
	assert_eq(outcome1.hits[0].amount, outcome2.hits[0].amount, "same seed → same damage")


# ── Condition-path crit via SpellResolver ───────────────────────────────────

func test_condition_path_self_loop_crits() -> void:
	# Graph: 0(atk) -- 1(self_loop). Seed the spell on 1, max_hops 2, FanAll.
	# Wave 0: 1 hit (predecessor=null, no crit — first hit doesn't crit, #353).
	# Wave 1: 1's neighbours after enemy filter: {1, 1} (self-loop contributes
	# two copies). With reducer=null, first-wins; the surviving state has
	# predecessor=1 AND current_node=1 → SelfLoopCritCondition fires (#353
	# predicate: state.predecessor == target).
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 1]], self)  # 1 has a self-loop
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), null,
			{max_hops = 2, max_visits_per_node = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	spell.crit_conditions = [SelfLoopCritCondition.new()]
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var hits_by_node := H.new().hits_by_node(outcome)
	var hits_on_1: Array = hits_by_node[n[1]]
	# Wave 0 hit (seed) + Wave 1 hit (self-loop traversal, merged from 2 incidents).
	assert_eq(hits_on_1.size(), 2, "seed + self-loop traversal")
	assert_false(hits_on_1[0].is_crit, "seed (predecessor=null) never crits")
	assert_true(hits_on_1[1].is_crit, "self-loop traversal crits (predecessor == target)")


func test_condition_path_leaf_crits() -> void:
	# 0(atk) -- 1 -- {2, 3}, all of 1/2/3 owned by D. N1 has entity degree 2
	# (N2 + N3); N2 has entity degree 1 → leaf.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [1, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), null, {max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	spell.crit_conditions = [LeafCritCondition.new()]
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var hits_by_node := H.new().hits_by_node(outcome)
	var hit_n2: Array = hits_by_node[n[2]]
	assert_eq(hit_n2.size(), 1)
	assert_true(hit_n2[0].is_crit, "N2 is a leaf (entity degree 1) → crit")
	var hit_n1: Array = hits_by_node[n[1]]
	assert_eq(hit_n1.size(), 1)
	assert_false(hit_n1[0].is_crit, "N1 has entity degree 2 → not a leaf")


# ── Combined paths ──────────────────────────────────────────────────────────

func test_both_paths_can_fire_tier_2() -> void:
	# Self-loop node 1, seeded there, max_hops 2: wave-1 self-loop traversal
	# crits via the condition path (predecessor==target); crit_chance 1.0 fires
	# the stat path on every landing → wave-1 lands at tier 2.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 1.0
	atk.stat_board.get_stat(&"crit_multiplier").base_value = 2.0
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), null,
			{max_hops = 2, max_visits_per_node = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	spell.crit_conditions = [SelfLoopCritCondition.new()]
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var hits_by_node := H.new().hits_by_node(outcome)
	var hits_on_1: Array = hits_by_node[n[1]]
	# Seed at wave 0 (stat-only → tier 1) + self-loop traversal at wave 1
	# (stat + condition → tier 2).
	assert_eq(hits_on_1.size(), 2, "seed + self-loop traversal")
	assert_true(hits_on_1[1].is_crit)
	assert_eq(hits_on_1[1].crit_multiplier, 2.0)
	# Wave-1 hit dmg: the seed carried verbatim (null hop_damage = identity),
	# and the first-wins null reducer keeps incidents[0].damage = seed (see
	# _apply_reducer's null shortcut), ×2 crit (caster multiplier).
	var seed_dmg: float = helper.seed_multiplier(n[0]) * spell.power
	assert_almost_eq(hits_on_1[1].amount, seed_dmg * 2.0, 0.001,
			"wave-1 self-loop traversal: seed × 2 (multiplier applied once)")
	# Find the event for the wave-1 self-loop landing (the SECOND event on n[1]).
	var event_tier: int = -1
	var seen_n1_events: int = 0
	for ev in outcome.timeline:
		if ev.target == n[1]:
			seen_n1_events += 1
			if seen_n1_events == 2:
				event_tier = ev.crit_tier
				break
	assert_eq(event_tier, 2, "wave-1 self-loop traversal: both stat AND condition path → tier 2")


func test_zero_damage_landing_never_crits() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 1.0
	var config := helper.make_config(helper.no_step(), helper.owner_enemy(), null, {max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 0.0)
	spell.crit_conditions = [SelfLoopCritCondition.new()]
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 0)
	assert_eq(outcome.timeline[0].crit_tier, 0)


func test_entity_without_board_still_supports_condition_path() -> void:
	# Self-loop node 1, seeded there, max_hops 2. Without a stat board, the
	# stat path is skipped entirely; the condition path alone fires on the
	# self-loop traversal (predecessor==target, see #353). Crit multiplier
	# falls back to 2.0.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 1]], self)
	var atk := helper.make_entity(graph, "A")
	atk.stat_board = null  # no board at all
	helper.assign_owner(graph, atk, [0])
	var def := helper.make_entity(graph, "D")
	helper.assign_owner(graph, def, [1])
	var config := helper.make_config(helper.fan_all(), helper.owner(OwnerFilter.Scope.ANY), null,
			{max_hops = 2, max_visits_per_node = 2})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	spell.crit_conditions = [SelfLoopCritCondition.new()]
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var hits_on_1: Array = H.new().hits_by_node(outcome).get(n[1], [])
	# Seed hit (no crit) + self-loop traversal (condition-path crit).
	assert_eq(hits_on_1.size(), 2)
	assert_false(hits_on_1[0].is_crit, "seed never crits")
	assert_true(hits_on_1[1].is_crit, "self-loop traversal crits without a stat board")
	assert_eq(hits_on_1[1].crit_multiplier, 2.0, "fallback multiplier 2.0")
