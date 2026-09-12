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
const _REVERBERATOR := preload("res://attack/spell/defs/reverberator.tres")


func _assert_well_formed(s: SpellDef, label: String) -> void:
	assert_not_null(s.propagation, "%s lost its propagation" % label)
	assert_true(s.propagation is PropagationConfig, "%s propagation is PropagationConfig" % label)
	assert_true(s.on_hit_effects.size() >= 1, "%s lost on-hit effects" % label)
	assert_not_null(s.targeting, "%s lost targeting" % label)
	assert_gt(s.power, 0.0, "%s lost its power coefficient" % label)


func test_spark_preset_well_formed() -> void:
	var s: SpellDef = _SPARK
	_assert_well_formed(s, "spark.tres")
	assert_eq(s.propagation.max_hops, 0, "spark is single-target")


func test_lightning_preset_well_formed() -> void:
	var s: SpellDef = _LIGHTNING
	_assert_well_formed(s, "lightning_bolt.tres")
	var p := s.propagation as PropagationConfig
	assert_eq(p.max_hops, 3, "lightning max_hops")
	assert_not_null(p.hop_damage, "lightning has a hop progression")
	assert_true(p.hop_damage is MultiplyProgression, "lightning uses MultiplyProgression")
	assert_almost_eq(p.hop_damage.factor, 0.5, 0.001)
	assert_not_null(p.spread, "lightning has a step (FanAll)")
	assert_true(p.spread is FanAllSpread)
	assert_not_null(p.reducer, "lightning has a reducer (MaxDamage)")
	assert_true(p.reducer is MaxDamageReducer)


func test_leafblower_preset_well_formed() -> void:
	var s: SpellDef = _LEAFBLOWER
	_assert_well_formed(s, "leafblower.tres")
	var p := s.propagation as PropagationConfig
	assert_true(p.spread is FanAllSpread)
	assert_true(p.filter is CompositeFilter, "leafblower composes owner + degree filter")
	assert_not_null(p.hop_damage, "leafblower has a hop progression")
	assert_true(p.hop_damage is MultiplyProgression, "leafblower uses MultiplyProgression")
	assert_gt(p.hop_damage.factor, 1.0, "leafblower ramps up")


func test_bruiser_preset_well_formed() -> void:
	var s: SpellDef = _BRUISER
	_assert_well_formed(s, "bruiser.tres")
	var p := s.propagation as PropagationConfig
	assert_true(p.spread is TakeTopNSpread)
	var step := p.spread as TakeTopNSpread
	assert_not_null(step.ranker, "bruiser step has a ranker")
	assert_true(step.ranker is StatRanker)
	# Authored explicitly rather than left on the export default, so the intent
	# is visible in the content. The cap ties across one entity's nodes (#660),
	# so ranking on it would not rank at all — see test_stat_ranker.gd (#702).
	assert_eq((step.ranker as StatRanker).stat_id, &"node_health__current",
		"bruiser homes by CURRENT health, not by the pool cap")


func test_reverberator_preset_well_formed() -> void:
	var s: SpellDef = _REVERBERATOR
	_assert_well_formed(s, "reverberator.tres")
	var p := s.propagation as PropagationConfig
	assert_true(p.spread is FanAllSpread, "reverberator fans to every candidate that clears the degree filter")
	assert_true(p.filter is CompositeFilter, "reverberator composes owner + degree filter")
	assert_true(p.reducer is SumDamageReducer, "reverberator uses SUM merger")
	assert_not_null(p.hop_damage, "reverberator has a hop progression")
	assert_true(p.hop_damage is ScaledAddProgression, "reverberator ramps additively off the seed")
	assert_gt(p.hop_damage.seed_fraction_per_hop, 0.0, "reverberator ramps up per hop")
	assert_gt(p.max_visits_per_node, 1, "reverberator allows revisits to weaponise self-loops")


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
	# seed = spell_damage(cast-from node) × power (D-32) — read the multiplier
	# off the fixture board so an INT-coefficient retune (#278) doesn't move it.
	var seed_dmg: float = helper.seed_multiplier(n[0]) * _SPARK.power
	assert_almost_eq(outcome.hits[0].amount, seed_dmg, 0.001)


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
	var seed_dmg: float = helper.seed_multiplier(n[0]) * _LIGHTNING.power
	assert_almost_eq(helper.total_damage_on(outcome, n[1]), seed_dmg, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[2]), seed_dmg * 0.5, 0.001)
	assert_almost_eq(helper.total_damage_on(outcome, n[3]), seed_dmg * 0.25, 0.001)


## --- catalogue-wide lints ----------------------------------------------------
##
## Everything above pins five hand-picked presets. These two sweep
## [constant SpellCatalog.ALL], so a spell added later is covered the day it
## lands rather than the day someone remembers to add a case.

## #851 moved the TrailBlazer's junction slam out of the step and into a
## [ScaleDamageEffect]. That effect scales `state.damage` IN PLACE and emits
## nothing; [DamageEffect] is what emits. So a ScaleDamageEffect authored AFTER
## the DamageEffect it means to scale leaves this landing's damage untouched —
## silently. It still reaches the next hop (mint reads `payload.damage`), so it
## isn't a total no-op and this is deliberately NOT a `SpellDef.validate()`
## error: validate() is a hard runtime gate in `BattleSystem.launch_attack`, and
## an author who genuinely wants "scale the next hop, not this landing" must not
## be locked out of casting. An authoring-time lint is the right altitude — if a
## spell ever wants that ordering on purpose, add it to the exemption below with
## a reason.
func test_no_shipped_spell_scales_damage_after_emitting_it() -> void:
	for spell in SpellCatalog.ALL:
		if spell == null:
			continue
		assert_eq(_late_scale_index(spell.on_hit_effects), -1,
			"%s authors a ScaleDamageEffect after its DamageEffect — the scale "
			% spell.name + "cannot reach damage that effect already emitted")


## The detector above, proven on a synthetic bad spell — a catalogue sweep that
## has only ever been green cannot tell you it would catch anything.
func test_the_effect_order_lint_actually_catches_a_late_scale() -> void:
	var damage := DamageEffect.new()
	var scale := ScaleDamageEffect.new()
	assert_eq(_late_scale_index([damage, scale] as Array[OnHitEffect]), 1,
			"scale AFTER damage is the failure the catalogue sweep looks for")
	assert_eq(_late_scale_index([scale, damage] as Array[OnHitEffect]), -1,
			"scale BEFORE damage is the correct authoring (the Trailblazer's)")
	assert_eq(_late_scale_index([scale] as Array[OnHitEffect]), -1,
			"a scale with nothing to emit after it is not this defect")


## Index of the first [ScaleDamageEffect] authored after a [DamageEffect] has
## already emitted, or -1 when the ordering is sound.
func _late_scale_index(effects: Array[OnHitEffect]) -> int:
	var emitted_at := -1
	for i in effects.size():
		var eff: OnHitEffect = effects[i]
		if eff is DamageEffect and emitted_at < 0:
			emitted_at = i
		elif eff is ScaleDamageEffect and emitted_at >= 0:
			return i
	return -1


## A spread with no hops never runs, and hops with no spread never leave the
## seed — either way the authored half is dead weight the tooltip then has to
## collapse (see [method PropagationConfig.get_description]). Catches a preset
## that lost one half to an editor refresh.
func test_every_shipped_spell_authors_hops_and_spread_together() -> void:
	for spell in SpellCatalog.ALL:
		if spell == null or spell.propagation == null:
			continue
		var p := spell.propagation
		var propagates: bool = p.max_hops > 0
		var has_spread: bool = p.spread != null and not (p.spread is NoSpread)
		assert_eq(propagates, has_spread,
			("%s: max_hops=%d but spread=%s — a spell either propagates "
			+ "(hops > 0 AND a real spread) or it does not.")
			% [spell.name, p.max_hops, p.spread])
