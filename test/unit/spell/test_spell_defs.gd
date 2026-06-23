extends GutTest

## Regression coverage for the shipped .tres spell presets. Catches the
## "editor refresh silently stripped a field" failure mode called out in
## .claude/rules/godot-workflow.md — runtime parse passes, the spell just
## generates wrong content. Asserts on structural sanity + a representative
## cast outcome.

const H := preload("res://test/unit/spell/spell_test_helper.gd")
const _SPARK := preload("res://attack/spell/defs/spark.tres")
const _LIGHTNING := preload("res://attack/spell/defs/lightning_bolt.tres")


func test_spark_preset_has_required_fields() -> void:
	var s: SpellDef = _SPARK
	assert_not_null(s.propagation, "spark.tres lost its propagation field")
	assert_true(s.on_hit_effects.size() >= 1, "spark.tres lost its on-hit effects")
	assert_not_null(s.targeting, "spark.tres lost its targeting")
	assert_gt(s.base_damage, 0.0, "spark.tres lost base_damage")
	assert_true(s.propagation is NoPropagation, "spark.tres uses NoPropagation")


func test_lightning_preset_has_required_fields() -> void:
	var s: SpellDef = _LIGHTNING
	assert_not_null(s.propagation, "lightning_bolt.tres lost its propagation")
	assert_true(s.propagation is AllNeighboursPropagation)
	var prop := s.propagation as AllNeighboursPropagation
	assert_eq(prop.max_hops, 3, "lightning max_hops")
	assert_almost_eq(prop.damage_multiplier_per_hop, 0.5, 0.001)
	assert_true(s.on_hit_effects.size() >= 1)
	assert_not_null(s.targeting)


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
	# 0(atk) - 1 - 2 - 3 line, seed at 1, lightning has max_hops=3 x0.5.
	var graph := helper.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var atk := helper.make_entity(graph, "A")
	var def := helper.make_entity(graph, "D")
	helper.give_big_hp(def)
	helper.assign_owner(graph, def, [1, 2, 3])
	helper.assign_owner(graph, atk, [0])
	var n := graph.get_skill_nodes()
	var outcome := SpellResolver.resolve(_LIGHTNING, n[1], n[0], atk, graph)
	# base_damage=10 → seed 10, hop1 5, hop2 2.5. (hop3 would be on a 4-line; we have 4 nodes already.)
	var base := _LIGHTNING.base_damage
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), base, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[2]), base * 0.5, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[3]), base * 0.25, 0.001)
