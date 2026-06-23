extends GutTest

## DamageEffect: produces one MAGIC DamageInstance per applied state. Skips
## states with non-positive damage (e.g. fully decayed via per-hop
## multipliers) or null current_node. Origin = predecessor on hops, falls
## back to source on the seed (so the first projectile launches from the
## cast-from node, not from nowhere).

const H := preload("res://test/unit/spell/spell_test_helper.gd")


func test_skips_zero_damage_state() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	helper.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.current_node = n[1]
	state.source = n[0]
	state.damage = 0.0
	var outcome := AttackOutcome.new()
	DamageEffect.new().apply(state, outcome)
	assert_eq(outcome.hits.size(), 0)


func test_skips_null_current_node() -> void:
	var state := CastSpell.new()
	state.damage = 10.0
	state.current_node = null
	var outcome := AttackOutcome.new()
	DamageEffect.new().apply(state, outcome)
	assert_eq(outcome.hits.size(), 0)


func test_origin_is_source_on_seed() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	helper.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.current_node = n[1]
	state.source = n[0]
	state.predecessor = null  # seed
	state.damage = 7.0
	var outcome := AttackOutcome.new()
	DamageEffect.new().apply(state, outcome)
	assert_eq(outcome.hits.size(), 1)
	assert_eq(outcome.hits[0].origin, n[0], "seed origin = source")
	assert_eq(outcome.hits[0].type, DamageInstance.Type.MAGIC)


func test_origin_is_predecessor_on_hop() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.current_node = n[2]
	state.source = n[0]
	state.predecessor = n[1]  # hop, not seed
	state.damage = 3.0
	var outcome := AttackOutcome.new()
	DamageEffect.new().apply(state, outcome)
	assert_eq(outcome.hits[0].origin, n[1], "hop origin = predecessor")
