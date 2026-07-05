extends GutTest

## TrailBlazerStep: the single-path "string walker". Two layers of coverage —
##   1. step() branch logic in isolation (continue vs slam, each terminal mode);
##   2. an end-to-end resolve through SpellResolver on a real string graph,
##      asserting the stock +2-ramp / ×2-slam damage sequence.

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


# ── helpers ──────────────────────────────────────────────────────────────

func _ctx(graph: Graph) -> PropagationContext:
	var c := PropagationContext.new()
	c.graph = graph
	return c


func _payload(damage: float, current: SkillNode, hops: int = 5) -> CastSpell:
	var p := CastSpell.new()
	p.damage = damage
	p.current_node = current
	p.hops_remaining = hops
	p.visited = [current] as Array[SkillNode]
	return p


## The production filter shape: enemy-owned AND absolute degree >= 2.
func _trail_blazer_config(opts: Dictionary = {}) -> PropagationConfig:
	var deg2 := ExpressionFilter.new()
	deg2.expression = "to_degree >= 2"
	var children: Array[PropagationFilter] = [h.owner_enemy(), deg2]
	var o := {max_hops = 20}
	o.merge(opts)
	return h.make_config(TrailBlazerStep.new(), h.composite_filter(children), null, o)


# ── step() branch logic ──────────────────────────────────────────────────

func test_continue_hop_adds_increment_and_keeps_walking() -> void:
	# node1 has degree 2 (0-1-2) → a continuation, not a slam.
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	step.per_hop_increment = 2.0
	var config := h.make_config(step, null, null, {max_hops = 5})
	var out := step.step(nodes[0], _payload(3.0, nodes[0]), [nodes[1]] as Array[SkillNode], config, _ctx(graph))
	assert_eq(out.size(), 1, "one branch minted")
	assert_almost_eq(out[0].damage, 5.0, 0.001, "3 + 2 increment")
	assert_eq(out[0].hops_remaining, 4, "decremented, walk continues")


func test_terminal_multiply_constant_slams_and_stops() -> void:
	# node0 has degree 3 (star 0-1,0-2,0-3) → a junction.
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	step.per_hop_increment = 2.0
	step.terminal_mode = TrailBlazerStep.TerminalMode.MULTIPLY_CONSTANT
	step.terminal_multiplier = 2.0
	var config := h.make_config(step, null, null, {max_hops = 5})
	var out := step.step(nodes[1], _payload(9.0, nodes[1]), [nodes[0]] as Array[SkillNode], config, _ctx(graph))
	assert_almost_eq(out[0].damage, 22.0, 0.001, "(9 + 2) × 2")
	assert_eq(out[0].hops_remaining, 0, "slam terminates the walk")


func test_terminal_square() -> void:
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	step.per_hop_increment = 1.0
	step.terminal_mode = TrailBlazerStep.TerminalMode.SQUARE
	var config := h.make_config(step, null, null, {max_hops = 5})
	var out := step.step(nodes[1], _payload(5.0, nodes[1]), [nodes[0]] as Array[SkillNode], config, _ctx(graph))
	assert_almost_eq(out[0].damage, 36.0, 0.001, "(5 + 1)² = 36")


func test_terminal_multiply_by_degree_scales_with_junction() -> void:
	# node0 degree 4 (0-1,0-2,0-3,0-4).
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3], [0, 4]], self)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	step.per_hop_increment = 1.0
	step.terminal_mode = TrailBlazerStep.TerminalMode.MULTIPLY_BY_DEGREE
	var config := h.make_config(step, null, null, {max_hops = 5})
	var out := step.step(nodes[1], _payload(5.0, nodes[1]), [nodes[0]] as Array[SkillNode], config, _ctx(graph))
	assert_almost_eq(out[0].damage, 24.0, 0.001, "(5 + 1) × degree 4")


func test_empty_candidates_ends_walk() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(TrailBlazerStep.new(), null, null, {max_hops = 5})
	var out := TrailBlazerStep.new().step(nodes[0], _payload(3.0, nodes[0]), [] as Array[SkillNode], config, _ctx(graph))
	assert_eq(out.size(), 0, "no candidate → no branch")


# ── end-to-end through the resolver ──────────────────────────────────────

func test_walks_string_and_slams_junction_end_to_end() -> void:
	# Enemy string: A(0)-B(1)-C(2)-D(3)-E(4)-F(5); F is a degree-3 junction
	# (5-6, 5-7 hang off it). Attacker owns a disjoint 8-9 territory to cast from.
	var graph := h.make_graph(
		[[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [5, 7], [8, 9]], self)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	h.assign_owner(graph, defender, [0, 1, 2, 3, 4, 5, 6, 7])
	h.assign_owner(graph, attacker, [8, 9])

	var effects: Array[OnHitEffect] = [DamageEffect.new()]
	var spell := h.make_spell(_trail_blazer_config(), effects, 1.0)
	var nodes := graph.get_skill_nodes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var out := SpellResolver.resolve(spell, nodes[0], nodes[8], attacker, graph, rng)

	assert_almost_eq(h.total_damage_on(out, nodes[0]), 1.0, 0.001, "A: seed base")
	assert_almost_eq(h.total_damage_on(out, nodes[1]), 3.0, 0.001, "B: 1 + 2")
	assert_almost_eq(h.total_damage_on(out, nodes[2]), 5.0, 0.001, "C: 3 + 2")
	assert_almost_eq(h.total_damage_on(out, nodes[3]), 7.0, 0.001, "D: 5 + 2")
	assert_almost_eq(h.total_damage_on(out, nodes[4]), 9.0, 0.001, "E: 7 + 2")
	assert_almost_eq(h.total_damage_on(out, nodes[5]), 22.0, 0.001, "F: (9 + 2) × 2 slam")
	assert_almost_eq(h.total_damage_on(out, nodes[6]), 0.0, 0.001, "past junction, walk stopped")
	assert_almost_eq(h.total_damage_on(out, nodes[7]), 0.0, 0.001, "past junction, walk stopped")
