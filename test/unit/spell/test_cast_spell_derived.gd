extends GutTest

## The one copy routine for a [CastSpell]. A stock reducer's merged payload used
## to be built field-by-field and silently reset Cyclone's came_from and
## closed_cycle; those now ride a [CycloneFront] in [member CastSpell.extras],
## which every stock merge folds through the extension, so both survive a
## convergence.

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
	var front := _front_template.seed(null) as CycloneFront.State
	front.came_from = [from] as Array[SkillNode]
	c.extras.append(front)
	return c


var _front_template := CycloneFront.new()


func test_a_sum_merge_keeps_came_from_and_closed_cycle() -> void:
	var graph := h.make_graph([[0, 2], [1, 2]], self)
	var n := graph.get_skill_nodes()
	var incidents: Array[CastSpell] = [_incident(n[2], n[0], 3.0), _incident(n[2], n[1], 4.0)]

	var merged := SumDamageReducer.new().reduce(incidents, PropagationContext.new())

	assert_almost_eq(merged.damage, 7.0, 0.0001, "the reducer still owns damage")
	var front := merged.extra(CycloneFront.ID) as CycloneFront.State
	assert_true(front.came_from.has(n[0]), "came_from survives the merge")
	assert_false(front.closed_cycle, "no incident closed, so neither does the merge")
	(incidents[1].extra(CycloneFront.ID) as CycloneFront.State).closed_cycle = true
	merged = SumDamageReducer.new().reduce(incidents, PropagationContext.new())
	assert_true((merged.extra(CycloneFront.ID) as CycloneFront.State).closed_cycle,
			"closed_cycle survives the merge")


func test_derived_leaves_the_deliberate_non_copies_at_their_defaults() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	var parent := _incident(n[1], n[0], 5.0)
	parent.arrival_share = 0.25
	parent.incident_count = 3
	parent.arrived_from = [n[0]] as Array[SkillNode]

	var child := CastSpell.derived(parent)

	assert_eq(child.damage, 0.0, "damage is the reducer's / the mint's")
	assert_eq(child.arrival_share, 1.0, "arrival_share is one arc's telemetry")
	assert_eq(child.incident_count, 1, "incident_count is a resolver fact")
	assert_true(child.arrived_from.is_empty(), "arrived_from is a resolver fact")
	assert_eq(child.seed_node, parent.seed_node)
	assert_eq(child.hop_index, parent.hop_index)


func test_derived_never_shares_its_parents_arrays() -> void:
	var graph := h.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	var parent := _incident(n[1], n[0], 5.0)

	var child := CastSpell.derived(parent)
	child.visited.append(n[0])

	assert_eq(parent.visited.size(), 2, "the parent's trail is untouched")
