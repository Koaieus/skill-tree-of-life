extends GutTest

## #679 aim-time ghost preview: [method MagicAttackPlan.get_node_role] /
## [method MagicAttackPlan.get_range_visual] driven off the shadow
## [method SpellResolver.resolve] while a candidate is merely HOVERED
## (pushed in by [method PlayerInputController._push_magic_hover]), not yet
## committed as [member MagicAttackPlan.target]. Three angles:
##
##   1. Mutation freedom — the load-bearing acceptance: HP, ownership and
##      mana read identical before and after a preview runs.
##   2. Bruiser's HP-gradient climb is visible in the preview node/edge set
##      before commit — the acceptance that motivated #679.
##   3. Trail Blazer's string walk + terminal junction is visible in the
##      preview, on a walk well past the spell def's current max_hops=20,
##      proving the preview imposes no cap of its own — it just replays
##      whatever [SpellResolver] would have walked.
##
## All three drive [MagicAttackPlan] through its real click/hover entry
## points ([method MagicAttackPlan._on_node_left_clicked],
## [method MagicAttackPlan.set_hover_target]) and read the result back
## through the same public [HighlightProvider] surface the overlays use
## ([method HighlightProvider.get_node_role],
## [method MagicAttackPlan.get_range_visual]) — never the private
## `_preview_*` cache fields.

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


## Global-reach HOSTILE targeting, generous enough that every fixture's
## hovered node is always a legal click target — the preview only previews a
## hover that [method MagicAttackPlan._preview_target] accepts as valid.
##
## Every spell here also sets `min_degree = 0`. Since #728 the cast-from node
## is derived rather than clicked, so [SpellDef]'s default `min_degree = 1`
## would leave these single-owned-node attackers with no eligible caster and
## nothing to preview. These fixtures are about propagation, not about gating.
func _hostile_targeting(max_hops: int = 10) -> NodeTargeting:
	var t := NodeTargeting.new()
	t.ownership_filter = SkillNode.Ownership.HOSTILE
	var finder := HopRangeFinder.new()
	finder.max_hops = max_hops
	t.range_finder = finder
	return t


## Roles a preview-hit node is allowed to read as. A hovered-but-uncommitted
## seed reads PROPAGATION (source stays ORIGIN, nothing here is ever a
## committed target), so this exists only to keep the per-node assertions
## below readable rather than repeating the enum literal everywhere.
const _PROPAGATION := HighlightProvider.HighlightRole.PROPAGATION


## [SpellTestHelper.make_graph] adds nodes/edges straight to
## `skill_nodes_container` / `edges_container` (fine for these fixtures'
## other callers — the resolver itself only ever reads `Graph.get_neighbours`
## / entity degree, never the AStar mirror). [method Graph._ready] already
## ran by the time those children land, so its one-shot `node_added` /
## `edge_added` backfill missed them, and per .claude/rules/graph.md a direct
## container add never fires those signals itself — so `graph.navigator`
## (the AStar mirror [HopRangeFinder.gather] walks) stays empty and every
## targeting query here would silently see no valid targets at all.
##
## [method GraphMirror.wire_to] is idempotent and re-sweeps
## `graph.get_skill_nodes()` on every call, so a second call after the graph
## is fully built resyncs it — this is a test-local fix-up, not a workaround
## for anything in [MagicAttackPlan] itself.
func _resync_navigator(graph: Graph) -> void:
	graph.navigator.wire_to(graph)


# ── 1. mutation freedom ─────────────────────────────────────────────────

func test_preview_mutates_nothing_hp_ownership_or_mana() -> void:
	var graph := h.make_graph([[0, 1]], self)
	_resync_navigator(graph)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	h.assign_owner(graph, attacker, [0])
	h.assign_owner(graph, defender, [1])
	var nodes := graph.get_skill_nodes()
	nodes[1].restore_current_hp(40.0)

	var config := h.make_config(h.fan_all(), h.owner_enemy(), h.max_reducer(), {max_hops = 1})
	var effects: Array[OnHitEffect] = [DamageEffect.new()]
	var spell := h.make_spell(config, effects, 10.0)
	spell.targeting = _hostile_targeting()
	spell.min_degree = 0

	var plan := MagicAttackPlan.new()
	plan.attacker = attacker
	plan.spell = spell
	plan._on_node_left_clicked(nodes[0])  # picks the source

	var hp_before := nodes[1].get_current_hp()
	var owner_before := nodes[1].owned_by
	var mana_before: float = attacker.stat_board.get_stat(&"mana").current

	plan.set_hover_target(nodes[1])
	# Force the lazy preview to materialize, exactly as the overlays do on
	# the next repaint — get_node_role per node, get_range_visual once.
	var role := plan.get_node_role(nodes[1])
	var visual := plan.get_range_visual()

	assert_eq(nodes[1].get_current_hp(), hp_before, "preview must not change HP")
	assert_eq(nodes[1].owned_by, owner_before, "preview must not change ownership")
	assert_eq(attacker.stat_board.get_stat(&"mana").current, mana_before,
			"preview must not spend mana")
	assert_eq(role, _PROPAGATION,
			"the hovered candidate itself is the walk's seed landing")
	assert_false(visual == null or visual.is_empty(),
			"a resolvable hover should populate a range visual")


func test_a_second_preview_still_mutates_nothing() -> void:
	# Same fixture, hovered/read twice — guards against a cache that only
	# stays pure on the FIRST rebuild.
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	_resync_navigator(graph)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	h.assign_owner(graph, attacker, [0])
	h.assign_owner(graph, defender, [1, 2])
	var nodes := graph.get_skill_nodes()
	nodes[1].restore_current_hp(30.0)
	nodes[2].restore_current_hp(70.0)

	var config := h.make_config(h.take_top_n(h.stat_ranker(&"node_health"), 1),
			h.owner_enemy(), h.max_reducer(), {max_hops = 2})
	var effects: Array[OnHitEffect] = [DamageEffect.new()]
	var spell := h.make_spell(config, effects, 5.0)
	spell.targeting = _hostile_targeting()
	spell.min_degree = 0

	var plan := MagicAttackPlan.new()
	plan.attacker = attacker
	plan.spell = spell
	plan._on_node_left_clicked(nodes[0])

	var hp1_before := nodes[1].get_current_hp()
	var hp2_before := nodes[2].get_current_hp()

	plan.set_hover_target(nodes[1])
	plan.get_node_role(nodes[1])
	plan.get_node_role(nodes[2])
	plan.set_hover_target(nodes[2])
	plan.get_node_role(nodes[1])
	plan.get_node_role(nodes[2])

	assert_eq(nodes[1].get_current_hp(), hp1_before)
	assert_eq(nodes[2].get_current_hp(), hp2_before)


# ── hover-jitter cache guard (the "no frame hitch" acceptance) ────────────

func test_rehovering_the_same_node_does_not_repaint() -> void:
	# MagicAttackPlan.set_hover_target skips the state_changed emit on a
	# no-op re-hover so mouse jitter over an already-hovered node costs
	# nothing — the whole "cache per (source, target), recompute only on
	# CHANGE" story the preview leans on for the 800-node budget. This is
	# the cheap substitute for a benchmark: a signal-emission count, not a
	# frame-timed harness.
	var graph := h.make_graph([[0, 1]], self)
	_resync_navigator(graph)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, attacker, [0])
	h.assign_owner(graph, defender, [1])
	var nodes := graph.get_skill_nodes()

	var spell := h.make_spell(
			h.make_config(h.fan_all(), h.owner_enemy(), h.max_reducer(), {max_hops = 1}),
			[DamageEffect.new()] as Array[OnHitEffect], 1.0)
	spell.targeting = _hostile_targeting()
	spell.min_degree = 0

	var plan := MagicAttackPlan.new()
	plan.attacker = attacker
	plan.spell = spell
	plan._on_node_left_clicked(nodes[0])

	# A lambda captures a local BY VALUE (.claude/rules/testing.md) — count
	# into a single-element Array, not a plain int, or the closure's own copy
	# increments while this scope's `emit_count` never moves.
	var emit_count: Array[int] = [0]
	plan.state_changed.connect(func(): emit_count[0] += 1)

	plan.set_hover_target(nodes[1])
	assert_eq(emit_count[0], 1, "the first hover onto a new node repaints once")
	plan.set_hover_target(nodes[1])
	plan.set_hover_target(nodes[1])
	assert_eq(emit_count[0], 1, "re-hovering the SAME node must not repaint again")


# ── 2. Bruiser's HP-gradient climb ────────────────────────────────────────

func test_bruiser_climb_is_visible_in_the_preview_before_commit() -> void:
	# Seed at 1; from 1 the climb must prefer 2 (hp 80) over 3 (hp 20); from
	# 2 it must prefer 4 (hp 90) over 5 (hp 10) — proving it climbs hop over
	# hop, not just picks one highest neighbour once.
	#
	#      0(ATK) - 1 -+- 2 -+- 4
	#                  |     |
	#                  3     5
	var graph := h.make_graph([[0, 1], [1, 2], [1, 3], [2, 4], [2, 5]], self)
	_resync_navigator(graph)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	h.assign_owner(graph, attacker, [0])
	h.assign_owner(graph, defender, [1, 2, 3, 4, 5])
	var nodes := graph.get_skill_nodes()
	var n1: SkillNode = nodes[1]
	var n2: SkillNode = nodes[2]
	var n20: SkillNode = nodes[3]  # the low-HP branch off n1 — never climbed
	var n3: SkillNode = nodes[4]
	var n30: SkillNode = nodes[5]  # the low-HP branch off n2 — never climbed
	n1.restore_current_hp(100.0)
	n2.restore_current_hp(80.0)
	n20.restore_current_hp(20.0)
	n3.restore_current_hp(90.0)
	n30.restore_current_hp(10.0)

	# The real Bruiser shape: enemy-only, single highest-node_health neighbour
	# per hop, max-damage reduction, 3 hops.
	var config := h.make_config(
			h.take_top_n(h.stat_ranker(&"node_health"), 1, TakeTopNStep.Direction.HIGHEST),
			h.owner_enemy(), h.max_reducer(), {max_hops = 3})
	var spell := h.make_spell(config, [DamageEffect.new()] as Array[OnHitEffect], 4.0)
	spell.targeting = _hostile_targeting()
	spell.min_degree = 0

	var plan := MagicAttackPlan.new()
	plan.attacker = attacker
	plan.spell = spell
	plan._on_node_left_clicked(nodes[0])
	plan.set_hover_target(n1)

	assert_eq(plan.get_node_role(n1), _PROPAGATION, "seed lands on the hovered node")
	assert_eq(plan.get_node_role(n2), _PROPAGATION, "climbs to the higher-HP neighbour (80 > 20)")
	assert_eq(plan.get_node_role(n3), _PROPAGATION, "keeps climbing to the higher-HP neighbour (90 > 10)")
	assert_eq(plan.get_node_role(n20), HighlightProvider.HighlightRole.IN_RANGE,
			"the lower-HP branch is a valid target but never PART of the predicted climb")
	assert_eq(plan.get_node_role(n30), HighlightProvider.HighlightRole.IN_RANGE,
			"same for the second lower-HP branch, one hop deeper")

	var traversed_edges := _propagation_edges(plan.get_range_visual())
	assert_eq(traversed_edges.size(), 2, "exactly the two climbed edges: n1-n2 and n2-n3")
	assert_true(_has_edge(traversed_edges, n1, n2), "n1-n2 must be tagged PROPAGATION")
	assert_true(_has_edge(traversed_edges, n2, n3), "n2-n3 must be tagged PROPAGATION")
	assert_false(_has_edge(traversed_edges, n1, n20), "the un-climbed n1-n20 edge stays untagged")
	assert_false(_has_edge(traversed_edges, n2, n30), "the un-climbed n2-n30 edge stays untagged")


# ── 3. Trail Blazer's string walk + terminal junction ─────────────────────

func test_trail_blazer_walk_and_terminal_junction_are_visible_in_preview() -> void:
	# Source(8) -[cast]-> 0, a degree-2 string 0-1-2-3-4-5, junction at 5
	# (also touches 6 and 7 — entity degree 3). Same shape as the resolver's
	# own end-to-end fixture (test_line_killer_step.gd), just with the
	# source wired directly onto the tip so MagicAttackPlan's own targeting
	# reach accepts the hover. max_hops=50 — well past the spell DEF's
	# current max_hops=20 (#679: "do not assume 20") — to prove nothing in
	# the PREVIEW path imposes its own cap; termination comes entirely from
	# TrailBlazerStep hitting the junction, exactly like a real cast.
	var graph := h.make_graph(
			[[8, 0], [0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [5, 7]], self)
	_resync_navigator(graph)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	h.assign_owner(graph, attacker, [8])
	h.assign_owner(graph, defender, [0, 1, 2, 3, 4, 5, 6, 7])
	var nodes := graph.get_skill_nodes()

	var deg2 := ExpressionFilter.new()
	deg2.expression = "to_degree >= 2"
	var filter := h.composite_filter([h.owner_enemy(), deg2])
	var config := h.make_config(TrailBlazerStep.new(), filter, null,
			{max_hops = 50, hop_damage = h.flat_add_progression(2.0)})
	var spell := h.make_spell(config, [DamageEffect.new()] as Array[OnHitEffect], 1.0)
	spell.targeting = _hostile_targeting(50)
	spell.min_degree = 0

	var plan := MagicAttackPlan.new()
	plan.attacker = attacker
	plan.spell = spell
	plan._on_node_left_clicked(nodes[8])
	plan.set_hover_target(nodes[0])

	for i in range(0, 6):  # the whole walked string, tip through the junction
		assert_eq(plan.get_node_role(nodes[i]), _PROPAGATION,
				"node %d is on the walked string / is the junction itself" % i)
	for i in [6, 7]:  # past the junction — the walk stops there
		assert_ne(plan.get_node_role(nodes[i]), _PROPAGATION,
				"node %d is past the junction; the walk must not have reached it" % i)

	var traversed_edges := _propagation_edges(plan.get_range_visual())
	assert_eq(traversed_edges.size(), 5, "five stepped edges: 0-1,1-2,2-3,3-4,4-5")
	for i in range(0, 5):
		assert_true(_has_edge(traversed_edges, nodes[i], nodes[i + 1]),
				"edge %d-%d must be tagged PROPAGATION" % [i, i + 1])


# ── shared helpers ─────────────────────────────────────────────────────────

func _propagation_edges(visual: RangeVisual) -> Array[Edge]:
	var out: Array[Edge] = []
	if visual == null:
		return out
	for entry in visual.edges:
		if entry.role == _PROPAGATION:
			out.append(entry.edge)
	return out


func _has_edge(edges: Array[Edge], a: SkillNode, b: SkillNode) -> bool:
	for e in edges:
		if (e.from == a and e.to == b) or (e.from == b and e.to == a):
			return true
	return false
