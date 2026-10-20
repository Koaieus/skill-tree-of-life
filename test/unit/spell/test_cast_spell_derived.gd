extends GutTest

## The one copy routine for a [CastSpell]. A stock reducer's merged payload used
## to be built field-by-field and silently reset [member CastSpell.came_from]
## and [member CastSpell.closed_cycle]; the merge now derives from its first
## incident, so both survive a convergence.

const H := preload("res://test/unit/spell/spell_test_helper.gd")

var h: SpellTestHelper


func before_each() -> void:
	h = H.new()


func _incident(at: SkillNode, from: SkillNode, damage: float) -> CastSpell:
	var c := CastSpell.new()
	c.seed_node = from
	c.current_node = at
	c.predecessor = from
	c.damage = damage
	c.hops_remaining = 2.0
	c.hop_index = 1
	c.visited = [from, at] as Array[SkillNode]
	c.came_from = [from] as Array[SkillNode]
	c.closed_cycle = true
	return c


func test_a_sum_merge_keeps_came_from_and_closed_cycle() -> void:
	var graph := h.make_graph([[0, 2], [1, 2]], self)
	var n := graph.get_skill_nodes()
	var incidents: Array[CastSpell] = [_incident(n[2], n[0], 3.0), _incident(n[2], n[1], 4.0)]

	var merged := SumDamageReducer.new().reduce(incidents, PropagationContext.new())

	assert_almost_eq(merged.damage, 7.0, 0.0001, "the reducer still owns damage")
	assert_true(merged.came_from.has(n[0]), "came_from survives the merge")
	assert_true(merged.closed_cycle, "closed_cycle survives the merge")
