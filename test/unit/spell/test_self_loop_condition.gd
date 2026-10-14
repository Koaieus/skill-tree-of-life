extends GutTest

## [SelfLoopCondition] — crits when ANY merged front arrived from the landed
## node: [member CastSpell.arrived_from] is an unordered set, so order is moot.

var h: SpellTestHelper


func before_each() -> void:
	h = SpellTestHelper.new()


func _lctx(node: SkillNode, graph: Graph, predecessor: SkillNode, arrived: Array[SkillNode]) -> LandingContext:
	var c := PropagationContext.new()
	c.graph = graph
	var p := CastSpell.new()
	p.current_node = node
	p.graph = graph
	p.predecessor = predecessor
	p.arrived_from = arrived
	return LandingContext.for_test(p, node, c)


func test_crits_when_any_merged_front_is_the_self_loop_in_either_order() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	var cond := SelfLoopCondition.new()
	var self_first: Array[SkillNode] = [n[0], n[1]]
	var self_last: Array[SkillNode] = [n[1], n[0]]
	# The reducer kept the neighbour's predecessor: the old form missed it.
	assert_true(cond.evaluate(_lctx(n[0], graph, n[1], self_first)), "self-loop front listed first")
	assert_true(cond.evaluate(_lctx(n[0], graph, n[1], self_last)), "self-loop front listed last")


func test_no_crit_without_a_self_loop_front() -> void:
	var graph := h.make_graph([[0, 1], [1, 2]], self)
	var n := graph.get_skill_nodes()
	var cond := SelfLoopCondition.new()
	var from: Array[SkillNode] = [n[1], n[2]]
	assert_false(cond.evaluate(_lctx(n[0], graph, n[1], from)), "neighbours only")
	assert_false(cond.evaluate(_lctx(n[0], graph, null, [])), "seed: empty set")
