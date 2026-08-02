extends GutTest

## Resonator (#352) — the convergence-crit spell. Identity is shape-reading:
## branches fan with a flat +2 per hop; when two BFS wavefronts converge on
## the same node in the same wave they ADD and the landing crits (×2). Single
## incidents pass through; no convergence → no crit.
##
## X = base_damage (1), A = increment (2), crit ×2.
##   T2 single diamond A-{B,D}-C:           crit C = 4X + 8A
##   T3 triple-diamond chain (A,C,E crit):   4X+8A, 4X+16A, 4X+24A
##   T5 hexagon (3-hop convergence):        crit = 4X + 12A
##   T1 straight line / pentagon:            no convergence → no crit.
##
## Disables the stat crit path (crit_chance = 0) so the numbers pin purely
## to the condition path.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _RESONATOR := preload("res://attack/spell/defs/resonator.tres")


func _setup(adjacency: Array, attacker_indices: Array,
		defender_indices: Array) -> Array:
	var helper := H.new()
	var graph := helper.make_graph(adjacency, self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.give_big_hp(atk)
	helper.assign_owner(graph, def, defender_indices)
	helper.assign_owner(graph, atk, attacker_indices)
	return [helper, graph, atk, def]


# ── preset sanity ─────────────────────────────────────────────────────────


func test_resonator_preset_well_formed() -> void:
	var s: SpellDef = _RESONATOR
	assert_not_null(s.propagation, "Resonator has propagation")
	assert_not_null(s.crit_conditions, "Resonator has crit_conditions")
	assert_eq(s.crit_conditions.size(), 1)
	assert_true(s.crit_conditions[0] is ConvergenceCritCondition,
			"Resonator crits on convergence")
	var p := s.propagation as PropagationConfig
	assert_true(p.reducer is SumDamageReducer, "Resonator sums incidents")
	assert_not_null(p.hop_damage, "Resonator has a hop_damage ramp")
	assert_true(p.hop_damage is AddRamp, "Resonator uses AddRamp (flat per hop)")
	assert_almost_eq(p.hop_damage.increment, 2.0, 0.001, "Resonator +2 per hop")
	assert_eq(p.max_hops, 6, "Resonator max_hops 6")
	assert_eq(p.max_visits_per_node, 1, "Resonator uses default visit cap — clean diamond crit identity")


# ── predicate in isolation ────────────────────────────────────────────────


func test_convergence_condition_single_incident_no_crit() -> void:
	var c := ConvergenceCritCondition.new()
	var state := CastSpell.new()
	state.incident_count = 1
	assert_false(c.evaluate(state, null, null), "1 incident → no crit")


func test_convergence_condition_two_incidents_crit() -> void:
	var c := ConvergenceCritCondition.new()
	var state := CastSpell.new()
	state.incident_count = 2
	assert_true(c.evaluate(state, null, null), "2 incidents → crit")


func test_convergence_condition_three_incidents_crit() -> void:
	# Note: odd >2 still crits under Resonator's rule — the parity-rule
	# variant lives in Chromatic Cascade (#355), not here.
	var c := ConvergenceCritCondition.new()
	var state := CastSpell.new()
	state.incident_count = 3
	assert_true(c.evaluate(state, null, null), "3 incidents → crit under simple rule")


func test_convergence_condition_null_state_no_crit() -> void:
	var c := ConvergenceCritCondition.new()
	assert_false(c.evaluate(null, null, null))


# ── end-to-end through the resolver ───────────────────────────────────────


func test_diamond_convergence_crits() -> void:
	# Diamond 1-{2,3}-4. Seed at 1, both shoulders hit 4 in wave 2 →
	# 2 incidents SUM, ×2 crit. X=1, A=2: each shoulder carries 1+2+2=5,
	# sum 10, crit → 20.
	var ctx := _setup([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_RESONATOR, n[1], n[0], atk, graph)

	# Wave 0: seed at 1 (1 dmg).
	# Wave 1: shoulders at 2 and 3 (3 dmg each = 1 + 2).
	# Wave 2: convergence at 4 — 2 incidents(5+5=10), ×2 crit → 20.
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), 1.0, 0.001, "seed: base 1")
	assert_almost_eq(helper.total_damage_on(outcome, n[2]), 3.0, 0.001, "shoulder: 1 + 2")
	assert_almost_eq(helper.total_damage_on(outcome, n[3]), 3.0, 0.001, "shoulder: 1 + 2")
	var hits_4: Array = helper.hits_by_node(outcome).get(n[4], [])
	assert_eq(hits_4.size(), 1, "convergence merged into one hit")
	assert_true(hits_4[0].is_crit, "convergence crits")
	assert_almost_eq(hits_4[0].amount, 20.0, 0.001,
			"sum (5+5) × 2 crit = 20")


func test_straight_line_no_crit() -> void:
	# Line 1-2-3-4-5 — never more than one incident per node → no crit.
	var ctx := _setup(
		[[0, 1], [1, 2], [2, 3], [3, 4], [4, 5]], [0], [1, 2, 3, 4, 5])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_RESONATOR, n[1], n[0], atk, graph)
	for hit in outcome.hits:
		assert_false(hit.is_crit, "no convergence on a line — no crit")


func test_triod_converges_but_crits_under_simple_rule() -> void:
	# A-{B,D,F}-C: 3 incidents converge at C. Under Resonator's simple rule
	# (>= 2), this SUMS and crits. Parity-rule cancel lives on #355.
	# Seed 1, shoulders 2/3/4, converge 5.
	var ctx := _setup(
		[[0, 1], [1, 2], [1, 3], [1, 4], [2, 5], [3, 5], [4, 5]],
		[0], [1, 2, 3, 4, 5])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_RESONATOR, n[1], n[0], atk, graph)
	var hits_5: Array = helper.hits_by_node(outcome).get(n[5], [])
	# 3 incidents of (X+2A)=5 each (shoulder +A, apex hop +A) → sum 15 → crit ×2 = 30.
	# Note: Resonator's simple rule crits on ≥2 incidents; parity-rule cancel
	# lives on #355 (Chromatic Cascade).
	assert_eq(hits_5.size(), 1, "triod merged to one hit")
	assert_true(hits_5[0].is_crit, "triod crits under simple rule (parity off)")
	assert_almost_eq(hits_5[0].amount, 30.0, 0.001, "3 incidents × (1+2*2) × crit 2 = 30")


func test_hexagon_late_convergence_crits() -> void:
	# Hexagon 0-1-2-3-4-5-0. Seed at 0; two wavefronts meet at the opposite
	# node (3) in wave 3. Each wavefront carries (1 + 2*3) = 7; sum 14; crit 28.
	var ctx := _setup(
		[[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0]],
		[], [0, 1, 2, 3, 4, 5])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_RESONATOR, n[0], n[0], atk, graph)
	var hits_3: Array = helper.hits_by_node(outcome).get(n[3], [])
	assert_eq(hits_3.size(), 1, "hexagon opposite node merged to one hit")
	assert_true(hits_3[0].is_crit, "hexagon convergence crits")
	# (1 + 2*3) = 7 per incident × 2 incidents × crit 2 = 28.
	assert_almost_eq(hits_3[0].amount, 28.0, 0.001, "hexagon crit at 3 hops")


func test_double_diamond_compounds_additive_part() -> void:
	# Chained diamonds: A-{B,F}-C, C-{D,G}-E. Seed 1, wan front reconverges at
	# 2 (diamond 1), 2 fans to {3,4}, 2's neighbors both feed 5 (diamond 2).
	# Edges: 1-2,1-3 wait — need real adjacency. Let's use indices 1..5:
	#   1 → {2,3} → 4 (diamond 1: crit at 4)
	#   4 → {5,6} → 7 (diamond 2: crit at 7)
	# Each diamond's crit doubles the additive part: 1st crit = 4X+8A = 4+16=20;
	# 2nd crit = 4X+16A = 4+32=36. (Onward merged carries 4X+8A=20 into diamond 2;
	# each shoulder of diamond 2 = 20 + 2*2 = 24; sum 48; ×2 crit → 96.)
	# Working: post-diamond-1 merged state.damage = 5+5 = 10 (sum, pre-crit).
	# Then diamond 2 shoulders each get 10 + 2*2 = 14 (after 2 hops, +A each);
	# sum 28; crit 56. Wait — seed at 1 means hop 0 = 1; hop 1 = shoulders (3);
	# hop 2 = diamond 1 crit (10); hop 3 = diamond 2 shoulders (10+2=12 wait no).
	# Trail: hop0 1, hop1 3 (each shoulder), hop2 5 (sum, before crit), crit x2=10 dealt.
	# Onward state.damage = 5 (pre-crit). hop3 each shoulder = 5+2 = 7. hop 4 converge = 7+7=14, crit → 28.
	var adjacency := [[0, 1],
		[1, 2], [1, 3], [2, 4], [3, 4],
		[4, 5], [4, 6], [5, 7], [6, 7]]
	var ctx := _setup(adjacency, [0], [1, 2, 3, 4, 5, 6, 7])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_RESONATOR, n[1], n[0], atk, graph)

	# Diamond 1 crit (node 4): (1+(2*2))*2 = 5 per incident ×2 incidents = 10 sum,
	# ×2 crit → 20 dealt.
	var hits_4: Array = helper.hits_by_node(outcome).get(n[4], [])
	assert_eq(hits_4.size(), 1, "diamond 1 merges to one hit")
	assert_true(hits_4[0].is_crit, "diamond 1 crits")
	assert_almost_eq(hits_4[0].amount, 20.0, 0.001, "diamond 1 crit = 20")

	# Diamond 2 crit (node 7): onward merged damage from node 4 is 10 (pre-crit).
	# Shoulders of diamond 2 each carry 10 + A = 12; apex hop adds another +A so
	# each incident at 7 = 14; sum 28; ×2 crit → 56.
	var hits_7: Array = helper.hits_by_node(outcome).get(n[7], [])
	assert_eq(hits_7.size(), 1, "diamond 2 merges to one hit")
	assert_true(hits_7[0].is_crit, "diamond 2 crits")
	assert_almost_eq(hits_7[0].amount, 56.0, 0.001,
			"diamond 2 crit compounds: (10+2+2)*2 incidents × 2 crit = 56")