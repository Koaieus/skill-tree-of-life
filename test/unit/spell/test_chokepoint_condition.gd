extends GutTest

## [ChokepointCondition] — Girdle's crit: the landed node is a cut vertex of
## its owner's territory, anchored at that owner's core, read against THIS
## cast's world ([method PropagationContext.is_cut_vertex]).

const _WITHER := preload("res://effects/status/wither.tres")
## True until `SpellResolver._stamp_crit_conditions` stamps a status hit's
## condition tier (its `amount <= 0` gate skips a StatusInstance today).
const _STATUS_STAMP_GATED := true

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


func _lctx(node: SkillNode, graph: Graph, world: CombatWorld) -> LandingContext:
	var c := PropagationContext.new()
	c.graph = graph
	c.world = world
	var p := CastSpell.new()
	p.current_node = node
	p.graph = graph
	return LandingContext.for_test(p, node, c)


## 0 (core) — 1 (bridge) — 2 — 3 (leaf); square 0 — 4 — 5 — 6 — 0 with a
## tail 5 — 7. Node 1 islands 2 and 3; node 4 sits on a cycle.
func _territory() -> Array:
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3], [0, 4], [4, 5], [5, 6], [6, 0], [5, 7]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, defender, [0, 1, 2, 3, 4, 5, 6, 7])
	return [graph, graph.get_skill_nodes()]


func test_a_bridge_is_a_chokepoint_and_a_cycle_node_is_not() -> void:
	var t := _territory()
	var graph: Graph = t[0]
	var n: Array = t[1]
	var cond := ChokepointCondition.new()
	assert_true(cond.evaluate(_lctx(n[1], graph, CombatWorld.live())), "the bridge to the limb is a chokepoint")
	assert_false(cond.evaluate(_lctx(n[4], graph, CombatWorld.live())), "a node on the square is not")
	assert_false(cond.evaluate(_lctx(n[3], graph, CombatWorld.live())), "a leaf islands nothing")
	assert_true(cond.evaluate(_lctx(n[5], graph, CombatWorld.live())), "5 holds the tail 7")


func test_a_kill_earlier_in_the_cast_turns_a_cycle_node_into_a_chokepoint() -> void:
	var t := _territory()
	var graph: Graph = t[0]
	var n: Array = t[1]
	var world := CombatWorld.shadow()
	var lctx := _lctx(n[4], graph, world)
	assert_false(ChokepointCondition.new().evaluate(lctx), "on the untouched shadow 4 is on a cycle")
	world.combat_for(n[6]).take_damage(9999.0, null)
	assert_true(ChokepointCondition.new().evaluate(lctx),
			"6 died on the shadow: the square is broken and 4 now holds 5 and 7")
	assert_false(n[6].owned_by == null, "the live node never saw the kill")
	world.free_shadow()


func test_an_unowned_node_is_never_a_chokepoint() -> void:
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	var n := graph.get_skill_nodes()
	assert_false(ChokepointCondition.new().evaluate(_lctx(n[1], graph, CombatWorld.live())))


# ── Girdle, cast ─────────────────────────────────────────────────────────────

## 0 (core) — 1 — 2 (target) — 3 — 4, with 2 — 5; the attacker's 6 hangs off 4.
func _girdle_cast() -> Array:
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3], [3, 4], [2, 5], [4, 6]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, defender, [0, 1, 2, 3, 4, 5])
	h.give_big_hp(defender)
	var atk := h.make_entity(graph, "ATK", Color.RED)
	h.assign_owner(graph, atk, [6])
	var n := graph.get_skill_nodes()
	var spell: SpellDef = load("res://attack/spell/defs/girdle.tres")
	assert_not_null(spell, "girdle.tres is authored")
	return [n, SpellResolver.resolve(spell, n[2], n[6], atk, graph)]


func _hits_on(outcome: AttackOutcome, node: SkillNode, status: bool) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for hit in outcome.hits:
		if hit.target == node and (hit is StatusInstance) == status:
			out.append(hit)
	return out


func test_girdle_fans_outward_only_and_crits_every_landed_chokepoint() -> void:
	var r := _girdle_cast()
	var n: Array = r[0]
	var outcome: AttackOutcome = r[1]
	assert_true(_hits_on(outcome, n[0], false).is_empty(), "the core is nearer: never hit")
	assert_true(_hits_on(outcome, n[1], false).is_empty(), "1 is nearer the core than the target: never hit")
	for i in [2, 3, 4, 5]:
		assert_eq(_hits_on(outcome, n[i], false).size(), 1, "node %d past the ring is hit once" % i)
	assert_true(_hits_on(outcome, n[2], false)[0].is_crit, "the target bridge crits")
	assert_true(_hits_on(outcome, n[3], false)[0].is_crit, "a bridge inside the limb rings the bark again")
	assert_false(_hits_on(outcome, n[4], false)[0].is_crit, "a leaf is no chokepoint")
	assert_false(_hits_on(outcome, n[5], false)[0].is_crit, "a leaf is no chokepoint")


func test_girdle_lands_more_wither_on_a_chokepoint_than_on_a_leaf() -> void:
	if _STATUS_STAMP_GATED:
		pending("waits on the resolver stamping a status hit's condition tier")
		return
	var r := _girdle_cast()
	var n: Array = r[0]
	var outcome: AttackOutcome = r[1]
	var bridge := _hits_on(outcome, n[2], true)
	var leaf := _hits_on(outcome, n[4], true)
	assert_eq(bridge.size(), 1, "the bridge takes one wither rider")
	assert_eq(leaf.size(), 1, "the leaf takes one wither rider")
	if bridge.size() != 1 or leaf.size() != 1:
		return
	assert_eq((bridge[0] as StatusInstance).def, _WITHER)
	assert_true(bridge[0].is_crit, "the status hit takes its spell's condition crit")
	assert_almost_eq((bridge[0] as StatusInstance).power,
			(leaf[0] as StatusInstance).power * absf(bridge[0].crit_multiplier), 0.0001,
			"a chokepoint crit lands folded stacks × |crit_multiplier|")
