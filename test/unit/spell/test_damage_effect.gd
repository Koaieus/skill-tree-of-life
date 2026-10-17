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
	var lctx := LandingContext.for_test(state, n[1])
	DamageEffect.new().apply(lctx)
	assert_eq(lctx.cast.outcome.hits.size(), 0)


func test_skips_null_current_node() -> void:
	var state := CastSpell.new()
	state.damage = 10.0
	state.current_node = null
	var lctx := LandingContext.for_test(state, null)
	DamageEffect.new().apply(lctx)
	assert_eq(lctx.cast.outcome.hits.size(), 0)


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
	var lctx := LandingContext.for_test(state, n[1])
	DamageEffect.new().apply(lctx)
	var outcome := lctx.cast.outcome
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
	var lctx := LandingContext.for_test(state, n[2])
	DamageEffect.new().apply(lctx)
	assert_eq(lctx.cast.outcome.hits[0].origin, n[1], "hop origin = predecessor")


func _pierce_mod(op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = &"armor_pierce"
	m.operation = op
	m.value = value
	return m


## The spell stamps the cast-from node's local pierce, overlaid by its own
## authoring; uses_board_pierce off drops the board's.
func test_stamps_armor_pierce_from_the_source_node() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var atk := helper.make_entity(graph, "A")
	helper.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	n[0].add_local_modifier(_pierce_mod(StatModifier.Operation.ADD_BASE, -3.0))
	var state := CastSpell.new()
	state.current_node = n[1]
	state.source = n[0]
	state.damage = 7.0
	var lctx := LandingContext.for_test(state, n[1])
	DamageEffect.new().apply(lctx)
	var hit := lctx.cast.outcome.hits[0] as DamageInstance
	assert_not_null(hit.armor_pierce, "board pierce on the source node reaches the hit")
	assert_almost_eq(hit.armor_pierce.fold(8.0), 5.0, 0.001)

	var off := DamageEffect.new()
	off.uses_board_pierce = false
	var lctx2 := LandingContext.for_test(state, n[1])
	off.apply(lctx2)
	assert_null((lctx2.cast.outcome.hits[0] as DamageInstance).armor_pierce,
		"uses_board_pierce off with nothing authored stamps null despite board pierce")

	var half := DamageEffect.new()
	half.armor_pierce_modifiers = [_pierce_mod(StatModifier.Operation.MULTIPLY, 0.5)]
	var lctx3 := LandingContext.for_test(state, n[1])
	half.apply(lctx3)
	assert_almost_eq((lctx3.cast.outcome.hits[0] as DamageInstance).armor_pierce.fold(8.0), 2.5, 0.001,
		"(8 − 3) × 0.5")
