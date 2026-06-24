extends GutTest

## Regression coverage for the shipped .tres spell presets. Catches the
## "editor refresh silently stripped a field" failure mode called out in
## .claude/rules/godot-workflow.md — runtime parse passes, the spell just
## generates wrong content. Asserts on structural sanity + a representative
## cast outcome.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _SPARK := preload("res://attack/spell/defs/spark.tres")
const _LIGHTNING := preload("res://attack/spell/defs/lightning_bolt.tres")
const _LEAFBLOWER := preload("res://attack/spell/defs/leafblower.tres")
const _BRUISER := preload("res://attack/spell/defs/bruiser.tres")
const _RESONATOR := preload("res://attack/spell/defs/resonator.tres")


func _assert_well_formed(s: SpellDef, label: String) -> void:
	assert_not_null(s.propagation, "%s lost its propagation" % label)
	assert_true(s.propagation is PropagationConfig, "%s propagation is PropagationConfig" % label)
	assert_true(s.on_hit_effects.size() >= 1, "%s lost on-hit effects" % label)
	assert_not_null(s.targeting, "%s lost targeting" % label)
	assert_gt(s.base_damage, 0.0, "%s lost base_damage" % label)


func test_spark_preset_well_formed() -> void:
	var s: SpellDef = _SPARK
	_assert_well_formed(s, "spark.tres")
	assert_eq(s.propagation.max_hops, 0, "spark is single-target")


func test_lightning_preset_well_formed() -> void:
	var s: SpellDef = _LIGHTNING
	_assert_well_formed(s, "lightning_bolt.tres")
	var p := s.propagation as PropagationConfig
	assert_eq(p.max_hops, 3, "lightning max_hops")
	assert_almost_eq(p.damage_multiplier_per_hop, 0.5, 0.001)
	assert_not_null(p.step, "lightning has a step (FanAll)")
	assert_true(p.step is FanAllStep)
	assert_not_null(p.reducer, "lightning has a reducer (MaxDamage)")
	assert_true(p.reducer is MaxDamageReducer)


func test_leafblower_preset_well_formed() -> void:
	var s: SpellDef = _LEAFBLOWER
	_assert_well_formed(s, "leafblower.tres")
	var p := s.propagation as PropagationConfig
	assert_true(p.step is FanAllStep)
	assert_true(p.filter is CompositeFilter, "leafblower composes owner + degree filter")
	assert_gt(p.damage_multiplier_per_hop, 1.0, "leafblower ramps up")


func test_bruiser_preset_well_formed() -> void:
	var s: SpellDef = _BRUISER
	_assert_well_formed(s, "bruiser.tres")
	var p := s.propagation as PropagationConfig
	assert_true(p.step is TakeTopNStep)
	var step := p.step as TakeTopNStep
	assert_not_null(step.ranker, "bruiser step has a ranker")
	assert_true(step.ranker is StatRanker)


func test_resonator_preset_well_formed() -> void:
	var s: SpellDef = _RESONATOR
	_assert_well_formed(s, "resonator.tres")
	var p := s.propagation as PropagationConfig
	assert_true(p.reducer is SumDamageReducer, "resonator uses SUM merger")
	assert_gt(p.damage_multiplier_per_hop, 1.0, "resonator ramps up per hop")
	assert_gt(p.max_visits_per_node, 1, "resonator allows revisits to weaponise self-loops")


func test_spark_cast_produces_single_seed_hit() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2])
	helper.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_SPARK, n[1], n[0], atk, graph)
	assert_eq(outcome.hits.size(), 1, "Spark is single-target")
	assert_eq(outcome.hits[0].target, n[1])
	assert_almost_eq(outcome.hits[0].amount, _SPARK.base_damage, 0.001)


func test_lightning_cast_chains_with_halving_falloff() -> void:
	var helper := H.new()
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_LIGHTNING, n[1], n[0], atk, graph)
	var base := _LIGHTNING.base_damage
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), base, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[2]), base * 0.5, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[3]), base * 0.25, 0.001)
