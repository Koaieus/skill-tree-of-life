extends GutTest

## A bare [HitLanding] — no spell, no [LandingContext] — is enough for
## [ApplyStatusEffect] to emit its [StatusInstance] (ADR 0044): the one on-hit
## vocabulary every attack mode shares.

const _TEST_DEF := preload("res://test/fixtures/status/test_status.tres")


func test_apply_status_on_a_bare_landing_emits_one_status_carrying_its_facts() -> void:
	var attacker: Entity = autofree(Entity.new())
	var target: SkillNode = autofree(SkillNode.new())
	var origin: SkillNode = autofree(SkillNode.new())
	var primary := DamageInstance.new()
	var landing := HitLanding.new()
	landing.attacker = attacker
	landing.source = primary
	landing.origin = origin
	landing.target = target
	landing.structural_key = 0.5
	landing.paired = primary

	var eff := ApplyStatusEffect.new()
	eff.def = _TEST_DEF
	eff.power = 3.0
	# Untyped call: the test predates the contract it pins.
	var any_eff: Variant = eff
	any_eff.apply(landing)

	assert_eq(landing.hits.size(), 1, "one status emitted into the landing's sink")
	var status := landing.hits[0] as StatusInstance
	assert_not_null(status, "the emitted hit is a StatusInstance")
	if status == null:
		return
	assert_eq(status.def, _TEST_DEF)
	assert_almost_eq(status.power, 3.0, 0.0001)
	assert_eq(status.target, target)
	assert_eq(status.origin, origin)
	assert_eq(status.attacker, attacker)
	assert_eq(status.paired, primary, "the status rides the landing's primary hit")
	assert_almost_eq(status.structural_key, 0.5, 0.0001)
