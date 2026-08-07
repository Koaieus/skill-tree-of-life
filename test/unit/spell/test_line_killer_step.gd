extends GutTest

## TrailBlazerStep: the "string walker". Three layers of coverage —
##   1. step() branch logic in isolation (continue vs slam, each terminal mode);
##   2. fan-out — every surviving candidate propagates, no random single pick
##      (cb1caa0). A string can't distinguish the two, so these use branches;
##   3. an end-to-end resolve through SpellResolver on a real string graph,
##      asserting the stock +2-progression / ×2-slam damage sequence, written
##      as X/A expressions off the seed (`spell_damage × power`) — including a
##      mid-string seed, which splits into two probes walking opposite ways.

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


# ── helpers ──────────────────────────────────────────────────────────────

func _ctx(graph: Graph) -> PropagationContext:
	var c := PropagationContext.new()
	c.graph = graph
	return c


## Give EVERY node in the graph one owner and return it.
##
## Load-bearing, not boilerplate: `TrailBlazerStep` reads
## [method SkillNode.get_entity_degree], which is degree within the OWNER's
## induced subgraph. An unowned node has no owner to induce a subgraph from, so
## the accessor's null guard returns 0 — and a 0 never trips the `> 2` junction
## test. Before this helper, the step-level fixtures below built unowned graphs
## and so silently asserted GRAPH-degree behaviour while the production step
## walked entity degree. They passed for the wrong reason.
##
## A single owner for the whole string is also the honest model of the spell: the
## Trailblazer punishes ONE defender's long-stretched constellation, and on a
## fully-owned string entity degree and graph degree coincide — which is exactly
## why the end-to-end tests further down never caught the divergence.
func _own_all(graph: Graph) -> Entity:
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	var indices: Array = []
	for i in graph.get_skill_nodes().size():
		indices.append(i)
	h.assign_owner(graph, defender, indices)
	return defender


func _payload(damage: float, current: SkillNode, hops: int = 5) -> CastSpell:
	var p := CastSpell.new()
	p.damage = damage
	p.current_node = current
	p.hops_remaining = hops
	p.visited = [current] as Array[SkillNode]
	return p


## The production filter shape: enemy-owned AND absolute degree >= 2.
## Uses FlatAddProgression(2) on the config for the per-hop +2 (moved off the
## step in #351; renamed in #274 — the increment is absolute on purpose).
func _trail_blazer_config(opts: Dictionary = {}) -> PropagationConfig:
	var deg2 := ExpressionFilter.new()
	deg2.expression = "to_degree >= 2"
	var children: Array[PropagationFilter] = [h.owner_enemy(), deg2]
	var o := {max_hops = 20, hop_damage = h.flat_add_progression(2.0)}
	o.merge(opts)
	return h.make_config(TrailBlazerStep.new(), h.composite_filter(children), null, o)


# ── step() branch logic ──────────────────────────────────────────────────

func test_continue_hop_adds_increment_and_keeps_walking() -> void:
	# node1 has degree 2 (0-1-2) → a continuation, not a slam.
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	_own_all(graph)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	var config := h.make_config(step, null, null, {max_hops = 5, hop_damage = h.flat_add_progression(2.0)})
	var out := step.step(nodes[0], _payload(3.0, nodes[0]), [nodes[1]] as Array[SkillNode], config, _ctx(graph))
	assert_eq(out.size(), 1, "one branch minted")
	assert_almost_eq(out[0].damage, 5.0, 0.001, "3 + 2 increment")
	assert_eq(out[0].hops_remaining, 4, "decremented, walk continues")


func test_terminal_multiply_constant_slams_and_stops() -> void:
	# node0 has degree 3 (star 0-1,0-2,0-3) → a junction.
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	step.terminal_mode = TrailBlazerStep.TerminalMode.MULTIPLY_CONSTANT
	step.terminal_multiplier = 2.0
	var config := h.make_config(step, null, null, {max_hops = 5, hop_damage = h.flat_add_progression(2.0)})
	var out := step.step(nodes[1], _payload(9.0, nodes[1]), [nodes[0]] as Array[SkillNode], config, _ctx(graph))
	assert_almost_eq(out[0].damage, 22.0, 0.001, "(9 + 2) × 2")
	assert_eq(out[0].hops_remaining, 0, "slam terminates the walk")


func test_terminal_square() -> void:
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	step.terminal_mode = TrailBlazerStep.TerminalMode.SQUARE
	var config := h.make_config(step, null, null, {max_hops = 5, hop_damage = h.flat_add_progression(1.0)})
	var out := step.step(nodes[1], _payload(5.0, nodes[1]), [nodes[0]] as Array[SkillNode], config, _ctx(graph))
	assert_almost_eq(out[0].damage, 36.0, 0.001, "(5 + 1)² = 36")


func test_terminal_multiply_by_degree_scales_with_junction() -> void:
	# node0 degree 4 (0-1,0-2,0-3,0-4).
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3], [0, 4]], self)
	_own_all(graph)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	step.terminal_mode = TrailBlazerStep.TerminalMode.MULTIPLY_BY_DEGREE
	var config := h.make_config(step, null, null, {max_hops = 5, hop_damage = h.flat_add_progression(1.0)})
	var out := step.step(nodes[1], _payload(5.0, nodes[1]), [nodes[0]] as Array[SkillNode], config, _ctx(graph))
	assert_almost_eq(out[0].damage, 24.0, 0.001, "(5 + 1) × degree 4")


## The ONLY fixture in this file that can distinguish entity degree from graph
## degree — see docs/domain/degree.md. Every other test either leaves nodes
## unowned (both accessors collapse to 0 / to graph degree) or gives one entity
## the whole graph (the two are equal by construction).
##
##   DEF: 0 — 1 — 2        node 1: graph degree 3, entity degree 2
##            |
##   ATK:     3
##
## A foreign node brushing the string must NOT read as a junction. On graph
## degree node 1 is a 3 and the walk slams to a halt on the defender's own
## chain; on entity degree it is a 2 and the walk carries on, which is the
## spell's entire premise.
func test_foreign_neighbour_is_not_a_junction() -> void:
	var graph := h.make_graph([[0, 1], [1, 2], [1, 3]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	h.assign_owner(graph, defender, [0, 1, 2])
	h.assign_owner(graph, attacker, [3])
	var nodes := graph.get_skill_nodes()

	assert_eq(nodes[1].get_graph_degree(graph), 3, "graph degree sees the ATK node")
	assert_eq(nodes[1].get_entity_degree(graph), 2, "entity degree does not")

	var step := TrailBlazerStep.new()
	step.terminal_mode = TrailBlazerStep.TerminalMode.MULTIPLY_CONSTANT
	step.terminal_multiplier = 2.0
	var config := h.make_config(step, null, null,
			{max_hops = 5, hop_damage = h.flat_add_progression(2.0)})

	var out := step.step(nodes[0], _payload(3.0, nodes[0]),
			[nodes[1]] as Array[SkillNode], config, _ctx(graph))

	assert_almost_eq(out[0].damage, 5.0, 0.001, "3 + 2 — a continuation, NOT a ×2 slam")
	assert_eq(out[0].hops_remaining, 4, "the walk carries on past the foreign neighbour")


func test_empty_candidates_ends_walk() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var nodes := graph.get_skill_nodes()
	var config := h.make_config(TrailBlazerStep.new(), null, null, {max_hops = 5, hop_damage = h.flat_add_progression(2.0)})
	var out := TrailBlazerStep.new().step(nodes[0], _payload(3.0, nodes[0]), [] as Array[SkillNode], config, _ctx(graph))
	assert_eq(out.size(), 0, "no candidate → no branch")


# ── fan-out: every surviving candidate propagates (cb1caa0) ──────────────
# The walk used to rng.randi_range a SINGLE candidate. On a pure string that's
# indistinguishable (the filter + visit cap leave exactly one candidate per
# hop), so the string tests above pass either way — these are the only tests
# that can tell the two apart.

func test_branch_mints_every_surviving_candidate_not_a_random_one() -> void:
	# 1 and 2 both hang off seed 0 and both have degree 2 → both continue.
	var graph := h.make_graph([[0, 1], [1, 3], [0, 2], [2, 4]], self)
	_own_all(graph)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	var config := h.make_config(step, null, null, {max_hops = 5, hop_damage = h.flat_add_progression(2.0)})
	var candidates := [nodes[1], nodes[2]] as Array[SkillNode]

	var out := step.step(nodes[0], _payload(3.0, nodes[0]), candidates, config, _ctx(graph))

	assert_eq(out.size(), 2, "both candidates propagate — no random single pick")
	var landed := [out[0].current_node, out[1].current_node]
	assert_true(landed.has(nodes[1]), "branch to node 1 minted")
	assert_true(landed.has(nodes[2]), "branch to node 2 minted")
	for cast in out:
		assert_almost_eq(cast.damage, 5.0, 0.001, "each branch carries 3 + 2")


func test_branch_slams_the_junction_and_continues_the_string_in_parallel() -> void:
	# Off seed 0: node 1 is degree 2 (continue), node 2 is degree 4 (junction).
	# Both must be minted, each resolving on its own branch rule.
	var graph := h.make_graph(
		[[0, 1], [1, 3], [0, 2], [2, 4], [2, 5], [2, 6]], self)
	_own_all(graph)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	step.terminal_mode = TrailBlazerStep.TerminalMode.MULTIPLY_CONSTANT
	step.terminal_multiplier = 2.0
	var config := h.make_config(step, null, null, {max_hops = 5, hop_damage = h.flat_add_progression(2.0)})
	var candidates := [nodes[1], nodes[2]] as Array[SkillNode]

	var out := step.step(nodes[0], _payload(3.0, nodes[0]), candidates, config, _ctx(graph))

	assert_eq(out.size(), 2, "continuation and junction both minted")
	for cast in out:
		if cast.current_node == nodes[1]:
			assert_almost_eq(cast.damage, 5.0, 0.001, "continuation: 3 + 2")
			assert_eq(cast.hops_remaining, 4, "continuation keeps walking")
		else:
			assert_almost_eq(cast.damage, 10.0, 0.001, "junction slam: (3 + 2) × 2")
			assert_eq(cast.hops_remaining, 0, "junction terminates its branch")


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

	# X = seed (spell_damage on the cast-from node × power), A = 2 per hop.
	var x: float = h.seed_multiplier(nodes[8]) * spell.power
	var a := 2.0
	assert_almost_eq(h.total_damage_on(out, nodes[0]), x, 0.001, "A: seed X")
	assert_almost_eq(h.total_damage_on(out, nodes[1]), x + a, 0.001, "B: X + A")
	assert_almost_eq(h.total_damage_on(out, nodes[2]), x + 2.0 * a, 0.001, "C: X + 2A")
	assert_almost_eq(h.total_damage_on(out, nodes[3]), x + 3.0 * a, 0.001, "D: X + 3A")
	assert_almost_eq(h.total_damage_on(out, nodes[4]), x + 4.0 * a, 0.001, "E: X + 4A")
	assert_almost_eq(h.total_damage_on(out, nodes[5]), (x + 5.0 * a) * 2.0, 0.001,
			"F: (X + 5A) × 2 slam")
	assert_almost_eq(h.total_damage_on(out, nodes[6]), 0.0, 0.001, "past junction, walk stopped")
	assert_almost_eq(h.total_damage_on(out, nodes[7]), 0.0, 0.001, "past junction, walk stopped")


func test_seeded_mid_string_splits_into_two_probes_walking_both_ways() -> void:
	# Seeded in the MIDDLE of a string, the walk has a candidate on each side
	# and must probe BOTH ways — the natural read of "fans to every candidate".
	#
	#   A(0) — B(1) — C(2) — D(3) — E(4) < F(5)
	#                 seed                \ G(6)
	#
	# The two probes are deliberately ASYMMETRIC, so they can't both be
	# explained by one walk: the left probe dead-ends at the degree-1 leaf A
	# (the `to_degree >= 2` filter stops it), while the right probe ramps on
	# and slams the degree-3 junction E. Attacker casts from a disjoint 7-8.
	var graph := h.make_graph(
		[[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [4, 6], [7, 8]], self)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	h.assign_owner(graph, defender, [0, 1, 2, 3, 4, 5, 6])
	h.assign_owner(graph, attacker, [7, 8])

	var effects: Array[OnHitEffect] = [DamageEffect.new()]
	var spell := h.make_spell(_trail_blazer_config(), effects, 1.0)
	var nodes := graph.get_skill_nodes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var out := SpellResolver.resolve(spell, nodes[2], nodes[7], attacker, graph, rng)

	var x: float = h.seed_multiplier(nodes[7]) * spell.power
	var a := 2.0
	assert_almost_eq(h.total_damage_on(out, nodes[2]), x, 0.001, "C: seed X")
	# Both probes leave the seed on the same beat, so both carry X + A.
	assert_almost_eq(h.total_damage_on(out, nodes[1]), x + a, 0.001, "B: left probe, X + A")
	assert_almost_eq(h.total_damage_on(out, nodes[3]), x + a, 0.001, "D: right probe, X + A")
	# Left probe dies at the leaf; right probe carries on and slams.
	assert_almost_eq(h.total_damage_on(out, nodes[0]), 0.0, 0.001, "A: leaf, filtered out")
	assert_almost_eq(h.total_damage_on(out, nodes[4]), (x + 2.0 * a) * 2.0, 0.001,
			"E: (X + 2A) × 2 slam")
	assert_almost_eq(h.total_damage_on(out, nodes[5]), 0.0, 0.001, "past junction, stopped")
	assert_almost_eq(h.total_damage_on(out, nodes[6]), 0.0, 0.001, "past junction, stopped")
