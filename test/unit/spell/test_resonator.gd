extends GutTest

## Resonator (#352) — the convergence-crit spell. Identity is shape-reading:
## branches fan with a flat +2 per hop; when two BFS wavefronts converge on
## the same node in the same wave they ADD and the landing crits (×2). Single
## incidents pass through; no convergence → no crit.
##
## X = the seed (`spell_damage(cast-from node) × power`, D-32),
## A = increment (2, absolute — FlatAddProgression), crit ×2. Goldens are
## written as X/A expressions, never literals, so they pin the SHAPE and
## survive an INT-coefficient retune (#278).
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


## X — the seed damage for this cast: `spell_damage(cast-from node) × power`.
func _x(helper: SpellTestHelper, source: SkillNode) -> float:
	return helper.seed_multiplier(source) * _RESONATOR.power


## A — the absolute per-hop increment authored on the preset.
func _a() -> float:
	return (_RESONATOR.propagation.hop_damage as FlatAddProgression).increment


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
	assert_not_null(p.hop_damage, "Resonator has a hop progression")
	assert_true(p.hop_damage is FlatAddProgression,
			"Resonator uses FlatAddProgression (absolute per hop, deliberately)")
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
	# 2 incidents SUM, ×2 crit. Each incident carries X+2A; sum 2X+4A;
	# crit → 4X+8A.
	var ctx := _setup([[0, 1], [1, 2], [1, 3], [2, 4], [3, 4]], [0], [1, 2, 3, 4])
	var helper: SpellTestHelper = ctx[0]
	var graph: Graph = ctx[1]
	var atk: Entity = ctx[2]
	atk.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_RESONATOR, n[1], n[0], atk, graph)

	# Wave 0: seed at 1 (X).
	# Wave 1: shoulders at 2 and 3 (X + A each).
	# Wave 2: convergence at 4 — 2 incidents of (X+2A), summed, ×2 crit.
	var x := _x(helper, n[0])
	var a := _a()
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), x, 0.001, "seed: X")
	assert_almost_eq(helper.total_damage_on(outcome, n[2]), x + a, 0.001, "shoulder: X + A")
	assert_almost_eq(helper.total_damage_on(outcome, n[3]), x + a, 0.001, "shoulder: X + A")
	var hits_4: Array = helper.hits_by_node(outcome).get(n[4], [])
	assert_eq(hits_4.size(), 1, "convergence merged into one hit")
	assert_true(hits_4[0].is_crit, "convergence crits")
	assert_almost_eq(hits_4[0].amount, 4.0 * x + 8.0 * a, 0.001,
			"sum 2×(X+2A) × 2 crit = 4X + 8A")


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
	# 3 incidents of (X+2A) → sum 3X+6A → crit ×2 = 6X+12A.
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
	# Note: Resonator's simple rule crits on ≥2 incidents; parity-rule cancel
	# lives on #355 (Chromatic Cascade).
	var x := _x(helper, n[0])
	var a := _a()
	assert_eq(hits_5.size(), 1, "triod merged to one hit")
	assert_true(hits_5[0].is_crit, "triod crits under simple rule (parity off)")
	assert_almost_eq(hits_5[0].amount, 6.0 * x + 12.0 * a, 0.001,
			"3 incidents × (X + 2A) × crit 2 = 6X + 12A")


func test_hexagon_late_convergence_crits() -> void:
	# Hexagon 0-1-2-3-4-5-0. Seed at 0; two wavefronts meet at the opposite
	# node (3) in wave 3. Each wavefront carries X + 3A; sum 2X+6A; crit 4X+12A.
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
	# (X + 3A) per incident × 2 incidents × crit 2 = 4X + 12A.
	var x := _x(helper, n[0])
	var a := _a()
	assert_almost_eq(hits_3[0].amount, 4.0 * x + 12.0 * a, 0.001, "hexagon crit at 3 hops")


func test_double_diamond_compounds_additive_part() -> void:
	# Chained diamonds: A-{B,F}-C, C-{D,G}-E. Seed 1, wan front reconverges at
	# 2 (diamond 1), 2 fans to {3,4}, 2's neighbors both feed 5 (diamond 2).
	# Edges: 1-2,1-3 wait — need real adjacency. Let's use indices 1..5:
	#   1 → {2,3} → 4 (diamond 1: crit at 4)
	#   4 → {5,6} → 7 (diamond 2: crit at 7)
	# The crit does not propagate: what travels onward from diamond 1 is the
	# merged PRE-crit damage 2X+4A. Diamond 2's shoulders add A (→ 2X+5A) and
	# its apex hop another A, so each incident at 7 is 2X+6A; sum 4X+12A;
	# crit ×2 → 8X+24A.
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

	# Diamond 1 crit (node 4): (X+2A) per incident × 2 incidents, ×2 crit.
	var x := _x(helper, n[0])
	var a := _a()
	var hits_4: Array = helper.hits_by_node(outcome).get(n[4], [])
	assert_eq(hits_4.size(), 1, "diamond 1 merges to one hit")
	assert_true(hits_4[0].is_crit, "diamond 1 crits")
	assert_almost_eq(hits_4[0].amount, 4.0 * x + 8.0 * a, 0.001, "diamond 1 crit = 4X + 8A")

	# Diamond 2 crit (node 7): onward merged damage from node 4 is 2X+4A
	# (pre-crit). Shoulders add A, the apex hop another A, so each incident at
	# 7 is 2X+6A; sum 4X+12A; ×2 crit → 8X+24A.
	var hits_7: Array = helper.hits_by_node(outcome).get(n[7], [])
	assert_eq(hits_7.size(), 1, "diamond 2 merges to one hit")
	assert_true(hits_7[0].is_crit, "diamond 2 crits")
	assert_almost_eq(hits_7[0].amount, 8.0 * x + 24.0 * a, 0.001,
			"diamond 2 crit compounds: 2×(2X+4A + 2A) × 2 crit = 8X + 24A")