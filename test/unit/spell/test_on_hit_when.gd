@tool
extends GutTest

## The one on-hit gate: [member OnHitEffect.when] is checked by
## [method OnHitEffect.run_all] for every effect, and [member SpellDef.rider_when]
## puts a gate on every intake rider of a cast.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _POISON := preload("res://effects/status/poison.tres")


## A fixed answer, or false only at the node named in [member not_at].
class _Cond:
	extends LandingCondition
	var result := true
	var not_at: SkillNode = null

	func evaluate(lctx: LandingContext) -> bool:
		if not_at != null:
			return lctx.node != not_at
		return result


func _cond(result: bool) -> _Cond:
	var c := _Cond.new()
	c.result = result
	return c


func _emitted_through_run_all(when: LandingCondition) -> int:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var n := graph.get_skill_nodes()
	var state := CastSpell.new()
	state.current_node = n[1]
	state.source = n[0]
	var lctx := LandingContext.for_test(state, n[1])
	var eff := ApplyStatusEffect.new()
	eff.def = _POISON
	eff.power = 2.0
	eff.when = when
	OnHitEffect.run_all([eff], lctx)
	return lctx.cast.outcome.hits.size()


func test_an_effect_whose_when_is_false_emits_nothing() -> void:
	assert_eq(_emitted_through_run_all(_cond(false)), 0, "when false: skipped")


func test_an_effect_whose_when_is_null_or_true_emits() -> void:
	assert_eq(_emitted_through_run_all(null), 1, "when null: always")
	assert_eq(_emitted_through_run_all(_cond(true)), 1, "when true: runs")


func test_a_when_on_a_non_spell_landing_runs_ungated() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1]], self)
	var landing := HitLanding.new()
	landing.target = graph.get_skill_nodes()[1]
	var eff := ApplyStatusEffect.new()
	eff.def = _POISON
	eff.power = 2.0
	eff.when = _cond(false)
	OnHitEffect.run_all([eff], landing)
	assert_push_error("needs a spell landing")
	assert_eq(landing.hits.size(), 1, "a plain HitLanding runs the gated effect anyway")


## Line 0(atk) - 1(seed) - 2, both enemy; fan_all, max_hops 1: two landings,
## a poison innate intake riding each. Returns [nodes, outcome].
func _cast(rider_when_false_at_seed: bool) -> Array:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	var config := helper.make_config(helper.fan_all(), helper.owner_enemy(), helper.max_reducer(),
			{max_hops = 1})
	var spell := helper.make_spell(config, [DamageEffect.new()], 10.0)
	var intake := AspectIntake.new()
	intake.identity = _POISON.identity
	intake.innate = 3
	spell.intakes = [intake] as Array[AspectIntake]
	var n := graph.get_skill_nodes()
	if rider_when_false_at_seed:
		var c := _Cond.new()
		c.not_at = n[1]
		spell.rider_when = c
	return [n, SpellResolver.resolve(spell, n[1], n[0], atk, graph)]


func _statuses_on(outcome: AttackOutcome, node: SkillNode) -> int:
	var count := 0
	for hit in outcome.hits:
		if hit is StatusInstance and hit.target == node:
			count += 1
	return count


func test_rider_when_false_on_the_seed_lands_no_rider_there() -> void:
	var r := _cast(true)
	var n: Array = r[0]
	assert_eq(_statuses_on(r[1], n[1]), 0, "gated off on the seed (wave 0)")
	assert_eq(_statuses_on(r[1], n[2]), 1, "still lands where the gate holds")


func test_rider_when_null_lands_the_rider_on_the_seed() -> void:
	var r := _cast(false)
	var n: Array = r[0]
	assert_eq(_statuses_on(r[1], n[1]), 1, "ungated: the seed carries the rider")
	assert_eq(_statuses_on(r[1], n[2]), 1, "and the next hop")


func test_trail_blazer_tres_gate_lands_on_the_inherited_when() -> void:
	var spell: SpellDef = load("res://attack/spell/defs/trail_blazer.tres")
	var scales := spell.on_hit_effects.filter(func(e): return e is ScaleDamageEffect)
	assert_eq(scales.size(), 1, "fixture: one authored scale")
	if scales.size() == 1:
		assert_true(scales[0].when is JunctionCondition, "the .tres `when` deserializes onto the base field")
