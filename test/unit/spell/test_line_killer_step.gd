extends GutTest

## TrailBlazerStep: the "string walker". Three layers of coverage —
##   1. step() in isolation — since #851 it is PURE SELECTION, so the only
##      branch left to assert is that there is none: a junction candidate
##      mints exactly like a chain candidate. The slam's own arithmetic lives
##      in `test_scale_damage_effect.gd`, which is where it moved to;
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
	# The from-side clause IS the stop (#851): nothing is eligible to leave a
	# junction, so the walk ends there without a step zeroing a counter.
	deg2.expression = "from_entity_degree <= 2 and to_degree >= 2"
	var children: Array[PropagationFilter] = [h.owner_enemy(), deg2]
	# Mirrors `trail_blazer.tres`: the hop budget is a SAFETY BACKSTOP, not a
	# tuning knob. The walk is meant to end at a junction, and termination is
	# guaranteed by `max_visits_per_node = 1` (never revisit), not by this.
	var o := {max_hops = 999, hop_damage = h.flat_add_progression(2.0)}
	o.merge(opts)
	return h.make_config(TrailBlazerStep.new(), h.composite_filter(children), null, o)


## The stock Trailblazer slam, now an on-hit effect authored before the damage
## effect rather than an `if` inside the step. Mirrors `trail_blazer.tres`.
func _slam() -> ScaleDamageEffect:
	var e := ScaleDamageEffect.new()
	e.when = JunctionCondition.new()
	e.mode = ScaleDamageEffect.Mode.MULTIPLY
	e.factor = 2.0
	return e


func _trail_blazer_effects() -> Array[OnHitEffect]:
	return [_slam(), DamageEffect.new()] as Array[OnHitEffect]


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


## The invariant that replaces the three old terminal-mode tests: the step no
## longer knows what a junction is. Its damage arithmetic and its hop counter
## are the same for a degree-4 junction as for a degree-2 link, and if anyone
## ever puts the slam back into the step this is what goes red. The slam's own
## numbers moved to `test_scale_damage_effect.gd`, unchanged.
func test_junction_candidate_mints_exactly_like_a_chain_candidate() -> void:
	# node0 is a degree-3 junction of the star 0-1,0-2,0-3; node1 is a plain
	# degree-1 neighbour. Both are minted by the same rule.
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	_own_all(graph)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	var config := h.make_config(step, null, null,
			{max_hops = 5, hop_damage = h.flat_add_progression(2.0)})
	var out := step.step(nodes[1], _payload(9.0, nodes[1]),
			[nodes[0]] as Array[SkillNode], config, _ctx(graph))
	assert_eq(out.size(), 1, "one branch minted")
	assert_almost_eq(out[0].damage, 11.0, 0.001,
			"9 + 2 — the ramp and nothing else; NO x2 slam at mint time")
	assert_eq(out[0].hops_remaining, 4,
			"the step does not zero the counter; the filter stops the walk")


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


func test_branch_mints_junction_and_chain_candidates_in_parallel() -> void:
	# Off seed 0: node 1 is degree 2, node 2 is degree 4 (a junction). Both
	# must be minted, and since #851 both carry the SAME ramped damage — the
	# junction's extra is applied when it lands, by the on-hit effect.
	var graph := h.make_graph(
		[[0, 1], [1, 3], [0, 2], [2, 4], [2, 5], [2, 6]], self)
	_own_all(graph)
	var nodes := graph.get_skill_nodes()
	var step := TrailBlazerStep.new()
	var config := h.make_config(step, null, null, {max_hops = 5, hop_damage = h.flat_add_progression(2.0)})
	var candidates := [nodes[1], nodes[2]] as Array[SkillNode]

	var out := step.step(nodes[0], _payload(3.0, nodes[0]), candidates, config, _ctx(graph))

	assert_eq(out.size(), 2, "chain and junction both minted")
	for cast in out:
		assert_almost_eq(cast.damage, 5.0, 0.001, "each branch carries 3 + 2, junction included")
		assert_eq(cast.hops_remaining, 4, "neither branch is terminated by the step")


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

	var effects := _trail_blazer_effects()
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

	var effects := _trail_blazer_effects()
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


## The ONE intended behaviour change in #851. **Owner, 2026-09-10: "Seed slams
## too"** — "when it reaches a junction" includes the first landing.
##
## It was never true before, and not by design: the slam was decided at
## child-mint inside the step, so hop 0 had no mint to be decided at. A cast
## seeded directly onto a junction took plain seed damage and then walked
## outward off the junction. Now the slam is an on-hit effect that fires where
## the spell lands, and the stop is a `from_entity_degree <= 2` filter clause
## that a junction fails — so both halves of "junction" apply to the seed for
## the same reason they apply to every other landing.
##
##   ATK: 7 — 8        DEF star: 1,2,3 around centre 0 (entity degree 3)
func test_seed_on_a_junction_slams_and_does_not_depart() -> void:
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3], [7, 8]], self)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	h.assign_owner(graph, defender, [0, 1, 2, 3])
	h.assign_owner(graph, attacker, [7, 8])

	var spell := h.make_spell(_trail_blazer_config(), _trail_blazer_effects(), 1.0)
	var nodes := graph.get_skill_nodes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var out := SpellResolver.resolve(spell, nodes[0], nodes[7], attacker, graph, rng)

	var x: float = h.seed_multiplier(nodes[7]) * spell.power
	assert_almost_eq(h.total_damage_on(out, nodes[0]), x * 2.0, 0.001,
			"the seed IS the junction, so it is slammed: X x 2")
	for i in [1, 2, 3]:
		assert_almost_eq(h.total_damage_on(out, nodes[i]), 0.0, 0.001,
				"nothing may leave a junction — arm %d untouched" % i)
	assert_eq(out.timeline.size(), 1, "one landing, no departure")
	assert_true(out.timeline[0].is_terminal,
			"the walk ENDED here, structurally — not merely by landing nothing else")


# ── the hop budget is a backstop, not a limiter ───────────────────────────

## A 25-node string is the Trailblazer's advertised dream target ("cast on a
## node at the end of a long string for maximum devastation") — and until
## 2026-09-02 it silently fizzled: `max_hops = 20` ran the budget out at hop 20,
## `SpellResolver` marked the walk terminal, and the junction slam never landed.
## The player got the whole ramp and none of the payoff, on exactly the shape
## the spell exists to punish.
func test_long_string_walks_past_the_old_20_hop_backstop_and_still_slams() -> void:
	# String 0-1-…-24-25, junction at 25 (edges to 24, 26, 27 → entity degree 3).
	# The walk is 25 hops long, comfortably past the retired 20-hop budget.
	var edges: Array = []
	for i in 25:
		edges.append([i, i + 1])
	edges.append([25, 26])
	edges.append([25, 27])
	edges.append([28, 29])  # disjoint attacker territory to cast from
	var graph := h.make_graph(edges, self)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	var defender_nodes: Array = []
	for i in 28:
		defender_nodes.append(i)
	h.assign_owner(graph, defender, defender_nodes)
	h.assign_owner(graph, attacker, [28, 29])

	var effects := _trail_blazer_effects()
	var spell := h.make_spell(_trail_blazer_config(), effects, 1.0)
	var nodes := graph.get_skill_nodes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var out := SpellResolver.resolve(spell, nodes[0], nodes[28], attacker, graph, rng)

	var x: float = h.seed_multiplier(nodes[28]) * spell.power
	var a := 2.0
	# Hop 21+ must still land — this is the assertion the old budget broke.
	assert_almost_eq(h.total_damage_on(out, nodes[21]), x + 21.0 * a, 0.001,
			"hop 21 lands (was truncated by the 20-hop budget)")
	assert_almost_eq(h.total_damage_on(out, nodes[24]), x + 24.0 * a, 0.001,
			"hop 24, the last link before the junction")
	assert_almost_eq(h.total_damage_on(out, nodes[25]), (x + 25.0 * a) * 2.0, 0.001,
			"junction slams at hop 25 — the payoff the truncation stole")
	assert_almost_eq(h.total_damage_on(out, nodes[26]), 0.0, 0.001,
			"past junction, walk stopped")
	assert_almost_eq(h.total_damage_on(out, nodes[27]), 0.0, 0.001,
			"past junction, walk stopped")


## Guards the AUTHORED value, not just the fixture — the bug lived in the
## `.tres`, so a test built on a hand-made config could never have caught it.
func test_authored_trail_blazer_hop_budget_clears_any_realistic_string() -> void:
	var spell: SpellDef = load("res://attack/spell/defs/trail_blazer.tres")
	assert_not_null(spell, "trail_blazer.tres loads")
	assert_not_null(spell.propagation, "trail_blazer has a propagation config")
	assert_gt(spell.propagation.max_hops, 200,
			"max_hops is a SAFETY BACKSTOP, not a tuning knob — the walk must be "
			+ "able to run the length of any realistic degree-2 string and reach "
			+ "its junction. Termination is guaranteed by max_visits_per_node = 1 "
			+ "(never revisit), so lowering this only truncates long strings.")
	assert_eq(spell.propagation.max_visits_per_node, 1,
			"the never-revisit cap is what actually bounds the walk")
