extends GutTest

## [DamageEffect] / [HealEffect] author their hit's denomination
## ([member HitInstance.basis]) and, for damage, its mitigation class
## ([member DamageInstance.type]) as two ORTHOGONAL exports — no coupling
## between "% of max hp" and "unmitigated" (owner call, 2026-09-16: no hard
## rule committed yet; orthogonal authoring until producers multiply enough
## to want a defaults table). The effect stamps exactly what was authored.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _payload() -> CastSpell:
	var s := CastSpell.new()
	s.current_node = autofree(_SKILL_NODE_SCENE.instantiate()) as SkillNode
	s.damage = 0.3
	return s


func test_damage_effect_stamps_authored_type_and_basis() -> void:
	var fx := DamageEffect.new()
	fx.type = DamageInstance.Type.TRUE
	fx.basis = HitInstance.AmountBasis.PERCENT_MAX
	var lctx := LandingContext.for_test(_payload(), null)
	fx.apply(lctx)
	var hit := lctx.cast.outcome.hits[0] as DamageInstance
	assert_eq(hit.type, DamageInstance.Type.TRUE)
	assert_eq(hit.basis, HitInstance.AmountBasis.PERCENT_MAX)
	assert_almost_eq(hit.amount, 0.3, 0.0001, "the coefficient, unresolved until land")


func test_damage_effect_defaults_stay_magic_and_flat() -> void:
	var fx := DamageEffect.new()
	var lctx := LandingContext.for_test(_payload(), null)
	fx.apply(lctx)
	var hit := lctx.cast.outcome.hits[0] as DamageInstance
	assert_eq(hit.type, DamageInstance.Type.MAGIC, "pre-#knob behaviour is the default")
	assert_eq(hit.basis, HitInstance.AmountBasis.FLAT)


func test_heal_effect_stamps_authored_basis() -> void:
	var fx := HealEffect.new()
	fx.basis = HitInstance.AmountBasis.PERCENT_MAX
	var lctx := LandingContext.for_test(_payload(), null)
	fx.apply(lctx)
	assert_eq((lctx.cast.outcome.hits[0] as HealInstance).basis, HitInstance.AmountBasis.PERCENT_MAX)
