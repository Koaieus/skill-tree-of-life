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
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var c := SelfLoopCritCondition.new()
	var n := graph.get_skill_nodes()
	assert_false(c.evaluate(null, n[0], null))


func test_self_loop_condition_target_has_self_loop_returns_true() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 0]], self)  # self-loop on N0
	var c := SelfLoopCritCondition.new()
	var n := graph.get_skill_nodes()
	assert_eq(n[0].self_loop_count, 1)
	assert_true(c.evaluate(null, n[0], null))


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
	# N1 is degree 2 (connected to N0 and N2)
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var c := LeafCritCondition.new()
	var state := CastSpell.new()
	state.graph = graph
	var n := graph.get_skill_nodes()
	assert_false(c.evaluate(state, n[1], null))


func test_leaf_condition_degree_1_returns_true() -> void:
	# N0 is degree 1 (only connected to N1)
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var c := LeafCritCondition.new()
	var state := CastSpell.new()
	state.graph = graph
	var n := graph.get_skill_nodes()
	assert_eq(graph.get_neighbours(n[0]).size(), 1)
	assert_true(c.evaluate(state, n[0], null))


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
	assert_almost_eq(hit.amount, 30.0, 0.001)


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
	# Graph: 0(atk) -- 1 -- 2(self_loop). Seed the spell on 1, it fans to 2.
	# Node 2 has a self-loop → SelfLoopCritCondition fires.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0  # disable stat path
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), null, {max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	spell.crit_conditions = [SelfLoopCritCondition.new()]
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var hits_by_node := H.new().hits_by_node(outcome)
	var hit_n2: Array = hits_by_node[n[2]]
	assert_eq(hit_n2.size(), 1)
	assert_true(hit_n2[0].is_crit, "N2 has a self-loop → condition-path crit")
	var hit_n1: Array = hits_by_node[n[1]]
	assert_eq(hit_n1.size(), 1)
	assert_false(hit_n1[0].is_crit, "N1 has no self-loop → no crit")


func test_condition_path_leaf_crits() -> void:
	# Line: 0(atk) -- 1 -- 2. N2 is degree 1 → leaf.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
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
	assert_true(hit_n2[0].is_crit, "N2 is a leaf (degree 1) → crit")
	var hit_n1: Array = hits_by_node[n[1]]
	assert_eq(hit_n1.size(), 1)
	assert_false(hit_n1[0].is_crit, "N1 has degree 2 → not a leaf")


# ── Combined paths ──────────────────────────────────────────────────────────

func test_both_paths_can_fire_tier_2() -> void:
	# Node with a self-loop AND crit_chance 1.0 → both paths fire → tier 2.
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	atk.stat_board.get_stat(&"crit_chance").base_value = 1.0
	atk.stat_board.get_stat(&"crit_multiplier").base_value = 2.0
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), null, {max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	spell.crit_conditions = [SelfLoopCritCondition.new()]
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[1], n[0], atk, graph)
	var hits_by_node := H.new().hits_by_node(outcome)
	var hit_n2: Array = hits_by_node[n[2]]
	assert_eq(hit_n2.size(), 1)
	assert_true(hit_n2[0].is_crit)
	assert_eq(hit_n2[0].crit_multiplier, 2.0)
	assert_almost_eq(hit_n2[0].amount, 20.0, 0.001, "base 10 × 2 (multiplier applied once, not stacked)")
	# Find the event for N2
	var event_tier: int = -1
	for ev in outcome.timeline:
		if ev.target == n[2]:
			event_tier = ev.crit_tier
			break
	assert_eq(event_tier, 2, "both stat AND condition path → tier 2")


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
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 2]], self)
	var atk := helper.make_entity(graph, "A")
	atk.stat_board = null  # no board at all
	var config := helper.make_config(helper.no_step(), helper.owner(OwnerFilter.Scope.ANY), null, {max_hops = 0})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	spell.crit_conditions = [SelfLoopCritCondition.new()]
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(spell, n[2], n[1], atk, graph)
	assert_eq(outcome.hits.size(), 1)
	assert_true(outcome.hits[0].is_crit, "condition path works even without a stat board")
	assert_eq(outcome.hits[0].crit_multiplier, 2.0, "fallback multiplier 2.0")
