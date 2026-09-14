extends GutTest

## ApplyStatusEffect (#878): pushes a StatusInstance carrying its OWN
## exported def/power (unlike DamageEffect/HealEffect, which read
## CastSpell.damage) — see attack/spell/on_hit/apply_status_effect.gd.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _TEST_DEF := preload("res://test/fixtures/status/test_status.tres")


func test_skips_null_current_node() -> void:
	var state := CastSpell.new()
	state.current_node = null
	var lctx := LandingContext.for_test(state, null)
	var eff := ApplyStatusEffect.new()
	eff.def = _TEST_DEF
	eff.power = 2.0
	eff.apply(lctx)
	assert_eq(lctx.cast.outcome.hits.size(), 0)


func test_skips_null_def() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.current_node = n[1]
	state.source = n[0]
	var lctx := LandingContext.for_test(state, n[1])
	var eff := ApplyStatusEffect.new()
	eff.def = null
	eff.apply(lctx)
	assert_eq(lctx.cast.outcome.hits.size(), 0)


func test_pushes_a_status_instance_with_def_and_power() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.current_node = n[1]
	state.source = n[0]
	state.predecessor = null  # seed
	var lctx := LandingContext.for_test(state, n[1])
	var eff := ApplyStatusEffect.new()
	eff.def = _TEST_DEF
	eff.power = 2.0
	eff.apply(lctx)
	var outcome := lctx.cast.outcome
	assert_eq(outcome.hits.size(), 1)
	var hit := outcome.hits[0] as StatusInstance
	assert_not_null(hit, "must push a StatusInstance")
	assert_eq(hit.def, _TEST_DEF)
	assert_almost_eq(hit.power, 2.0, 0.0001)
	assert_eq(hit.kind, HitInstance.Kind.STATUS)
	assert_eq(hit.target, n[1])
	assert_eq(hit.origin, n[0], "seed origin = source")


func test_origin_is_predecessor_on_hop() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.current_node = n[2]
	state.source = n[0]
	state.predecessor = n[1]  # hop, not seed
	var lctx := LandingContext.for_test(state, n[2])
	var eff := ApplyStatusEffect.new()
	eff.def = _TEST_DEF
	eff.power = 1.0
	eff.apply(lctx)
	assert_eq(lctx.cast.outcome.hits[0].origin, n[1], "hop origin = predecessor")


func test_get_description_pins_the_output() -> void:
	var eff := ApplyStatusEffect.new()
	eff.def = _TEST_DEF
	eff.power = 2.0
	assert_eq(eff.get_description(), "Applies Test Status (2).")


func test_get_description_with_no_def_does_not_crash() -> void:
	var eff := ApplyStatusEffect.new()
	assert_eq(eff.get_description(), "Applies a status.")
