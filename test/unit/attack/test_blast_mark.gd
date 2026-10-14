extends GutTest

## A board blast stamps itself on its hits ([BlastMark]) and [OutcomeApplier]
## announces it once per live apply ([signal Events.blast_landed]) — never on
## a shadow world. Reach is the sim's own radius_for, never a literal.

const _EXPLOSIVE := preload("res://effects/status/explosive.tres")
const _POISON := preload("res://effects/status/poison.tres")
const _BLIND := preload("res://effects/status/blindness.tres")

var _f: VolleyBoardFixture


func before_each() -> void:
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0
	_f.target.get_combat().apply_status(_EXPLOSIVE, 2.0)


func _rider(def: StatusDef) -> ApplyStatusEffect:
	var e := ApplyStatusEffect.new()
	e.def = def
	return e


## A DETONATE spell landing (load 3) on the charged target with two inners.
func _detonate() -> Array[HitInstance]:
	var cast := PropagationContext.new()
	cast.caster = _f.attacker
	cast.graph = _f.graph
	cast.world = CombatWorld.live()
	cast.outcome = AttackOutcome.new()
	cast.target_mask = SkillNode.Ownership.HOSTILE
	var payload := CastSpell.new()
	payload.current_node = _f.target
	payload.source = _f.leaves[0]
	payload.damage = 10.0
	var lctx := LandingContext.for_test(payload, _f.target, cast)
	var effects: Array[OnHitEffect] = [_rider(_POISON), _rider(_BLIND)]
	OnHitEffect.run_all(DetonateEffect.arm(effects, 3), lctx)
	return lctx.hits


## The hits the blast appended: everything off the centre.
func _inner(hits: Array[HitInstance]) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for h in hits:
		if h.target != _f.target:
			out.append(h)
	return out


func _outcome(hits: Array[HitInstance]) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.hits = hits
	return outcome


func test_one_mark_rides_every_inner_hit_at_the_sims_reach() -> void:
	var hits := _detonate()
	var inner := _inner(hits)
	assert_gt(inner.size(), 1, "fixture: the blast lands inner hits")
	var mark: BlastMark = inner[0].blast_mark
	assert_not_null(mark, "the blast stamps its hits")
	if mark == null:
		return
	for h in inner:
		assert_true(is_same(h.blast_mark, mark), "one mark on every inner hit")
	var spread := _EXPLOSIVE.spread as ExplosiveSpread
	var power := DetonateEffect.power_of(3, 2, spread.resonance)
	assert_almost_eq(mark.reach, spread.radius_for(_f.target.radius, power), 0.001, "the sim's reach")
	assert_eq(mark.power, power, "the detonation's power reaches the mark")
	assert_true(is_same(mark.centre, _f.target), "centred on the struck node")
	assert_true(is_same(mark.attacker, _f.attacker), "the attacker's blast")
	assert_eq(mark.riders, [_POISON.identity, _BLIND.identity] as Array[Identity],
			"riders are the inners' status identities, explosive stripped")
	for h in hits:
		if h.target == _f.target:
			assert_null(h.blast_mark, "the centre's own hits carry no mark")


func test_a_live_apply_announces_the_blast_once() -> void:
	var hits := _detonate()
	watch_signals(Events)
	await OutcomeApplier.apply(_outcome(hits), CombatWorld.live())
	assert_signal_emit_count(Events, "blast_landed", 1, "once per mark")


func test_a_shadow_apply_never_announces() -> void:
	var hits := _detonate()
	watch_signals(Events)
	await OutcomeApplier.apply(_outcome(hits), CombatWorld.shadow())
	assert_signal_emit_count(Events, "blast_landed", 0, "a shadow world has no audience")
