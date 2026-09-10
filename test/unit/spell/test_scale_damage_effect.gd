extends GutTest

## [ScaleDamageEffect] and [JunctionCondition] (#851, hub #849 Seam C).
##
## Most of this file is TRANSPLANTED coverage, not new coverage: the three
## slam-mode arithmetic cases (×2 → 22, SQUARE → 36, MULTIPLY_BY_DEGREE → 24)
## and the entity-vs-graph-degree junction case all lived in
## `test_line_killer_step.gd` while the slam lived inside `TrailBlazerStep`.
## The numbers are deliberately unchanged so the coverage moved rather than
## being re-derived — see the enumeration on issue #851.

const H := preload("res://test/unit/spell/spell_test_helper.gd")

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


func _own_all(graph: Graph) -> Entity:
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	var indices: Array = []
	for i in graph.get_skill_nodes().size():
		indices.append(i)
	h.assign_owner(graph, defender, indices)
	return defender


func _landing(damage: float, node: SkillNode, graph: Graph) -> CastSpell:
	var p := CastSpell.new()
	p.damage = damage
	p.current_node = node
	p.graph = graph
	return p


func _effect(mode: int, factor: float = 2.0, when: LandingCondition = null) -> ScaleDamageEffect:
	var e := ScaleDamageEffect.new()
	e.mode = mode as ScaleDamageEffect.Mode
	e.factor = factor
	e.when = when
	return e


# ── JunctionCondition ──────────────────────────────────────────────────────


func test_junction_is_false_at_degree_two_and_true_at_degree_three() -> void:
	# Chain 0-1-2 plus 1-3: node 1 is degree 3, node 2 is degree 1.
	var graph := h.make_graph([[0, 1], [1, 2], [1, 3]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var c := JunctionCondition.new()
	assert_true(c.evaluate(_landing(1.0, n[1], graph), n[1], null), "degree 3 is a junction")
	assert_false(c.evaluate(_landing(1.0, n[2], graph), n[2], null), "degree 1 is not")
	var chain := h.make_graph([[0, 1], [1, 2]], self)
	_own_all(chain)
	var cn := chain.get_skill_nodes()
	assert_false(c.evaluate(_landing(1.0, cn[1], chain), cn[1], null), "degree 2 is not")


## Transplanted from `test_line_killer_step.gd::test_foreign_neighbour_is_not_a
## _junction` — the ONE fixture that can tell entity degree from graph degree.
##
##   DEF: 0 — 1 — 2        node 1: graph degree 3, entity degree 2
##            |
##   ATK:     3
##
## A foreign node brushing the string must NOT read as a junction, or the
## Trailblazer slams to a halt on the defender's own chain. See
## `docs/domain/degree.md`.
func test_junction_reads_entity_degree_not_graph_degree() -> void:
	var graph := h.make_graph([[0, 1], [1, 2], [1, 3]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	h.assign_owner(graph, defender, [0, 1, 2])
	h.assign_owner(graph, attacker, [3])
	var n := graph.get_skill_nodes()

	assert_eq(n[1].get_graph_degree(graph), 3, "graph degree sees the ATK node")
	assert_eq(n[1].get_entity_degree(graph), 2, "entity degree does not")
	assert_false(JunctionCondition.new().evaluate(_landing(1.0, n[1], graph), n[1], null),
			"a foreign neighbour is not a junction")


func test_junction_without_a_graph_is_false() -> void:
	var graph := h.make_graph([[0, 1], [1, 2], [1, 3]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(1.0, n[1], graph)
	state.graph = null
	assert_false(JunctionCondition.new().evaluate(state, n[1], null))


# ── ScaleDamageEffect: the three modes ─────────────────────────────────────


func test_multiply_scales_by_factor() -> void:
	# Transplanted: (9 + 2) × 2 = 22, the stock Trailblazer slam.
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(11.0, n[0], graph)
	_effect(ScaleDamageEffect.Mode.MULTIPLY, 2.0).apply(state, AttackOutcome.new())
	assert_almost_eq(state.damage, 22.0, 0.001, "11 × 2")


func test_square_scales_quadratically() -> void:
	# Transplanted: (5 + 1)² = 36.
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(6.0, n[0], graph)
	_effect(ScaleDamageEffect.Mode.SQUARE).apply(state, AttackOutcome.new())
	assert_almost_eq(state.damage, 36.0, 0.001, "6² = 36")


func test_multiply_by_degree_reads_the_landed_nodes_entity_degree() -> void:
	# Transplanted: (5 + 1) × degree 4 = 24, on the same star 0-1,0-2,0-3,0-4.
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3], [0, 4]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(6.0, n[0], graph)
	_effect(ScaleDamageEffect.Mode.MULTIPLY_BY_DEGREE).apply(state, AttackOutcome.new())
	assert_almost_eq(state.damage, 24.0, 0.001, "6 × entity degree 4")


func test_multiply_by_degree_is_entity_degree_not_graph_degree() -> void:
	# node 1: graph degree 3, entity degree 2. The pipeline's degree rule holds
	# here too — the old `_terminal_damage` docstring claimed graph degree, but
	# the value it was handed was always the entity degree.
	var graph := h.make_graph([[0, 1], [1, 2], [1, 3]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	h.assign_owner(graph, defender, [0, 1, 2])
	h.assign_owner(graph, attacker, [3])
	var n := graph.get_skill_nodes()
	var state := _landing(5.0, n[1], graph)
	_effect(ScaleDamageEffect.Mode.MULTIPLY_BY_DEGREE).apply(state, AttackOutcome.new())
	assert_almost_eq(state.damage, 10.0, 0.001, "5 × 2, not 5 × 3")


# ── the `when` gate ────────────────────────────────────────────────────────


func test_null_condition_always_fires() -> void:
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(7.0, n[1], graph)
	_effect(ScaleDamageEffect.Mode.MULTIPLY, 3.0).apply(state, AttackOutcome.new())
	assert_almost_eq(state.damage, 21.0, 0.001, "no gate means unconditional")


func test_a_false_condition_leaves_damage_untouched() -> void:
	# Landing on a degree-2 link: JunctionCondition is false, so no scale.
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(7.0, n[1], graph)
	_effect(ScaleDamageEffect.Mode.MULTIPLY, 2.0, JunctionCondition.new()).apply(
			state, AttackOutcome.new())
	assert_almost_eq(state.damage, 7.0, 0.001, "untouched")


func test_a_true_condition_fires() -> void:
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(7.0, n[0], graph)
	_effect(ScaleDamageEffect.Mode.MULTIPLY, 2.0, JunctionCondition.new()).apply(
			state, AttackOutcome.new())
	assert_almost_eq(state.damage, 14.0, 0.001, "junction landing scales")


func test_scaling_emits_nothing_of_its_own() -> void:
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var outcome := AttackOutcome.new()
	_effect(ScaleDamageEffect.Mode.MULTIPLY, 2.0).apply(_landing(7.0, n[0], graph), outcome)
	assert_eq(outcome.hits.size(), 0, "it mutates state.damage; DamageEffect emits")


# ── ordering: authored BEFORE DamageEffect ─────────────────────────────────


func test_scaling_before_damage_effect_scales_the_emitted_instance() -> void:
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(7.0, n[0], graph)
	var outcome := AttackOutcome.new()
	for eff in [_effect(ScaleDamageEffect.Mode.MULTIPLY, 2.0), DamageEffect.new()]:
		eff.apply(state, outcome)
	assert_eq(outcome.hits.size(), 1, "only the damage effect emits")
	assert_almost_eq(outcome.hits[0].amount, 14.0, 0.001, "the emitted hit carries the scale")


func test_scaling_after_damage_effect_does_not_reach_the_emitted_instance() -> void:
	# The negative half of the ordering contract — the reason the .tres authors
	# the scale FIRST, stated as a test rather than as a comment.
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var n := graph.get_skill_nodes()
	var state := _landing(7.0, n[0], graph)
	var outcome := AttackOutcome.new()
	for eff in [DamageEffect.new(), _effect(ScaleDamageEffect.Mode.MULTIPLY, 2.0)]:
		eff.apply(state, outcome)
	assert_almost_eq(outcome.hits[0].amount, 7.0, 0.001, "already emitted, unscaled")
	assert_almost_eq(state.damage, 14.0, 0.001, "the state did scale — too late")
