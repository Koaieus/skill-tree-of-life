extends GutTest

## [PropagationContext.entity_degree_of] (#860) — the world-aware entity-degree
## read that [JunctionCondition], [LeafCondition], [ScaleDamageEffect]'s
## `MULTIPLY_BY_DEGREE`, [ExpressionFilter]'s `from_entity_degree`/
## `to_entity_degree` and [DegreeRanker] all go through now, instead of
## [method SkillNode.get_entity_degree] off the live node.
##
## The scenario every one of them shares: a cast's own EARLIER wave
## deallocates a node, and a LATER wave asks a degree question about one of
## that node's neighbours. Off the live node the answer is stale — nothing
## mutates `owned_by` until the whole attack replays on the real world
## (docs/domain/attack-timeline.md) — so the predicate must ask [CombatWorld]
## instead. There is no existing spell test that simulates a mid-cast kill;
## this is the first, built the way [method NodeCombat.take_damage] is
## actually driven in production (test_stat_ranker.gd's shadow fixture, with a
## LETHAL hit instead of a partial one, so the death cascade — the same
## [method EntityCombat.cascade_from] a live battle uses — actually strips the
## node on the shadow).

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


func _ctx(graph: Graph, world: CombatWorld) -> PropagationContext:
	var c := PropagationContext.new()
	c.graph = graph
	c.world = world
	return c


## [LandingCondition.evaluate] early-returns false on a null payload or a null
## [member CastSpell.graph] — both conditions need a real one, not just a real
## [PropagationContext].
func _payload(node: SkillNode, graph: Graph) -> CastSpell:
	var p := CastSpell.new()
	p.current_node = node
	p.graph = graph
	return p


# ── JunctionCondition ───────────────────────────────────────────────────────

## Star: 0 (core) — 1, 2, 3. Entity degree of 0 is 3 (a junction) until 1 dies.
func test_junction_condition_reads_the_post_kill_world_not_the_live_node() -> void:
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, defender, [0, 1, 2, 3])
	var n := graph.get_skill_nodes()

	var world := CombatWorld.shadow()
	var lctx := LandingContext.for_test(_payload(n[0], graph), n[0], _ctx(graph, world))

	assert_eq(lctx.entity_degree_of(n[0]), 3, "before the kill, the world agrees with the node")
	assert_true(JunctionCondition.new().evaluate(lctx), "degree 3 is a junction")

	# Wave 0's kill: node 1 dies on the SHADOW, exactly how a real cast's
	# lethal landing does (NodeCombat.take_damage -> EntityCombat.cascade_from).
	world.combat_for(n[1]).take_damage(9999.0, null)

	assert_eq(lctx.entity_degree_of(n[0]), 2,
			"the world sees the kill: node 1 no longer counts toward node 0's degree")
	assert_false(JunctionCondition.new().evaluate(lctx),
			"no longer a junction on the world THIS cast is walking")
	assert_eq(n[0].get_entity_degree(graph), 3,
			"the live node still says 3, by design — nothing but a replayed record mutates it")

	world.free_shadow()


func test_junction_condition_without_a_kill_matches_the_live_node() -> void:
	# Sanity: on an untouched shadow (and on a live world) this must read
	# identically to the pre-#860 direct-node read, everywhere no cast has
	# killed anything yet — the trail_blazer_spread.gd goldens depend on this.
	var graph := h.make_graph([[0, 1], [0, 2], [0, 3]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, defender, [0, 1, 2, 3])
	var n := graph.get_skill_nodes()
	var lctx := LandingContext.for_test(_payload(n[0], graph), n[0], _ctx(graph, CombatWorld.live()))
	assert_eq(lctx.entity_degree_of(n[0]), n[0].get_entity_degree(graph),
			"live world: the accessor and the node's own read agree")


# ── LeafCondition ────────────────────────────────────────────────────────────

## Chain 0 (core) — 1 — 2. Node 1's entity degree is 2 until node 2 dies,
## after which it drops to 1 and becomes a leaf.
func test_leaf_condition_reads_the_post_kill_world_not_the_live_node() -> void:
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.assign_owner(graph, defender, [0, 1, 2])
	var n := graph.get_skill_nodes()

	var world := CombatWorld.shadow()
	var lctx := LandingContext.for_test(_payload(n[1], graph), n[1], _ctx(graph, world))

	assert_false(LeafCondition.new().evaluate(lctx), "degree 2 is not a leaf yet")

	world.combat_for(n[2]).take_damage(9999.0, null)

	assert_eq(lctx.entity_degree_of(n[1]), 1, "node 2's death drops node 1 to degree 1")
	assert_true(LeafCondition.new().evaluate(lctx),
			"node 1 reads as a leaf on the world THIS cast made it one on")
	assert_eq(n[1].get_entity_degree(graph), 2,
			"the live node still says 2, by design")

	world.free_shadow()
