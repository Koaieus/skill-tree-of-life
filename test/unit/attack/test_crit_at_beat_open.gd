extends GutTest

## An arrow's or a blade contact's crit is decided as its beat opens, before
## either [Admits] read (ADR 0092 §2 "crit and load already in"; ADR 0083 §4):
## [method HitGather.stage_one] draws an undecided head off the resolve's crit
## stream, so the read sees the crit amount, the landing draws nothing more,
## the head's terrain stacks take its crit, and a replay draws nothing.
##
## The test [Admits] sits on the roster's own Lightning band, swapped in before
## each test and restored after; the heads are built the production way
## ([method HitLanding.riding] + [method HitLanding.place]).

const _D := 4.0
const _M := 2.0


## Logs every second read's arrivals: their head's crit and their amount.
class _LogAdmits extends Admits:
	var reads: Array = []

	func read(_node: SkillNode, _after: TerrainRead, arrivals: Array[Arrival]) -> AdmitsAnswer:
		for a in arrivals:
			reads.append({crit = a.head.is_crit, amount = a.amount})
		return AdmitsAnswer.new()


var _w: TestWorld
var _attacker: Entity
var _from: SkillNode
var _target: SkillNode
var _light: Element
var _fire: Element
var _light_bands: Array[ElementBand] = []
var _admits: _LogAdmits


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	var owner := _w.add_entity("Owner")
	_attacker = _w.add_entity("Attacker")
	await get_tree().process_frame
	_from = _w.add_node(&"From")
	_target = _w.add_node(&"Target")
	_w.link(_from, _target)
	var rest: Array[SkillNode] = []
	for i in 3:
		var n := _w.add_node(StringName("N%d" % i))
		_w.link(_target, n)
		rest.append(n)
	_w.allocate(_attacker, [_from])
	_w.allocate(owner, [_target] + rest)
	await get_tree().process_frame
	_light = ElementRoster.shared().by_id(&"lightning")
	_fire = ElementRoster.shared().by_id(&"fire")
	_light_bands = _light.bands.duplicate()
	_admits = _LogAdmits.new()
	var band := ElementBand.new()
	band.admits = _admits
	var lb: Array[ElementBand] = [band]
	_light.bands = lb
	var slice := CombatWorld.live().combat_for(_target)
	slice.add_terrain(_light, slice.terrain_threshold() + 1 - slice.charge())
	_stat(&"crit_multiplier", _M)


func after_each() -> void:
	_light.bands = _light_bands
	CombatWorld.reset_live()


func _stat(id: StringName, value: float) -> void:
	var s: Stat = _attacker.stat_board.get_stat(id)
	s.base_value = value


## An arrow on the target, its landing placed as [method RangedDamageFormula.ride]
## places one, with [param heat] stacks of Fire's terrain riding it.
func _arrow(heat := 0) -> Array[HitInstance]:
	var arrow := RangedDamageFormula.RangedHitInstance.new()
	arrow.amount = _D
	arrow.type = DamageInstance.Type.TRUE
	return _place(arrow, heat)


## A blade contact on the target, its landing placed as [SwingResolve] places
## one, no gate (its amount is stamped all the same).
func _contact() -> Array[HitInstance]:
	var di := BladeDamageInstance.new(BladeHitEvent.new(0.5, 1, -1, _target), null)
	di.amount = _D
	di.type = DamageInstance.Type.TRUE
	return _place(di, 0)


func _place(head: DamageInstance, heat: int) -> Array[HitInstance]:
	head.target = _target
	head.origin = _from
	head.attacker = _attacker
	var hits: Array[HitInstance] = [head]
	var landing := HitLanding.riding(head, hits)
	landing.target_mask = SkillNode.Ownership.HOSTILE
	if heat > 0:
		var fx := ApplyStatusEffect.new()
		fx.def = _fire.terrain
		fx.power = heat
		fx.apply(landing)
	landing.place()
	return hits


func _drain(hits: Array[HitInstance], rng: RandomNumberGenerator) -> void:
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(),
			BeatClock.instant_clock(), null, rng)


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1827
	return rng


## [param hits]' head's stamped raw amount, as the gather stamps it.
func _stamped(head: HitInstance) -> float:
	var probe := head.amount
	head.stamp_at_gather(CombatWorld.live())
	var stamped := head.amount
	head.amount = probe
	return stamped


func _check_read_pair(make: Callable, what: String) -> void:
	for cc: float in [1.0, 0.0]:
		_admits.reads.clear()
		_stat(&"crit_chance", cc)
		var hits: Array[HitInstance] = make.call()
		var head := hits[0]
		assert_true(head.is_head, "fixture: the %s heads its span" % what)
		var raw := _stamped(head)
		await _drain(hits, _rng())
		var crits := cc >= 1.0
		var m := _M if crits else 1.0
		assert_eq(_admits.reads.size(), 1, "the %s's arrival is read once (cc %s)" % [what, cc])
		if _admits.reads.is_empty():
			continue
		assert_eq(_admits.reads[0].crit, crits, "the read sees the %s's crit (cc %s)" % [what, cc])
		assert_almost_eq(float(_admits.reads[0].amount), raw * m, 0.001,
				"the read's amount is the %s's stamped damage × %s (cc %s)" % [what, m, cc])


# 1 ─────────────────────────────────────────────────────────────────────────────
func test_an_arrows_admits_read_sees_its_crit_and_crit_amount() -> void:
	await _check_read_pair(_arrow, "arrow")


# 2 ─────────────────────────────────────────────────────────────────────────────
func test_a_blade_contacts_admits_read_sees_its_crit_and_crit_amount() -> void:
	await _check_read_pair(_contact, "blade contact")


# 3 ─────────────────────────────────────────────────────────────────────────────
func test_the_landed_hit_carries_the_reads_crit_and_the_stream_draws_once() -> void:
	_stat(&"crit_chance", 0.5)
	var hits := _arrow()
	var rng := _rng()
	var once := _rng()
	var expect_crit := once.randf() < 0.5
	await _drain(hits, rng)
	assert_eq(rng.state, once.state, "the stream advanced exactly once for the arrow")
	assert_eq(_admits.reads.size(), 1, "fixture: one read")
	if _admits.reads.is_empty():
		return
	assert_eq(_admits.reads[0].crit, expect_crit, "the read saw the draw's crit")
	assert_eq(hits[0].is_crit, expect_crit, "the landed arrow carries the same crit")


## Two arrows in one beat draw in list order: the first arrow's draw is the
## stream's first.
func test_two_heads_of_one_beat_draw_in_list_order() -> void:
	_stat(&"crit_chance", 0.5)
	var rng := _rng()
	var probe := _rng()
	var first := probe.randf() < 0.5
	var second := probe.randf() < 0.5
	var hits := _arrow()
	hits.append_array(_arrow())
	var heads := hits.filter(func(h: HitInstance) -> bool: return h.is_head)
	assert_eq(heads.size(), 2, "fixture: two heads")
	await _drain(hits, rng)
	assert_eq(rng.state, probe.state, "two draws, one per arrow")
	assert_eq([heads[0].is_crit, heads[1].is_crit], [first, second], "drawn in list order")


# 4 ─────────────────────────────────────────────────────────────────────────────
func test_an_arrows_terrain_stacks_take_its_crit() -> void:
	_stat(&"crit_chance", 1.0)
	var slice := CombatWorld.live().combat_for(_target)
	var before := slice.terrain_count(_fire)
	await _drain(_arrow(2), _rng())
	assert_eq(slice.terrain_count(_fire) - before, int(2 * _M),
			"the Fire rider lands crit_multiplier × its stacks in stage one")


# 5 ─────────────────────────────────────────────────────────────────────────────
func test_a_rebuilt_record_draws_nothing_and_lands_its_recorded_crit() -> void:
	_stat(&"crit_chance", 1.0)
	var hits := _arrow(2)
	await _drain(hits, _rng())
	assert_true(hits[0].is_crit, "fixture: the fresh arrow crits")
	var outcome := AttackOutcome.new()
	outcome.hits = hits
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _w.graph)))
	var rebuilt := AttackRecord.rebuild(wired, _w.graph)
	assert_false(rebuilt.hits.any(func(h: HitInstance) -> bool: return h.is_head),
			"a rebuilt hit is no head: nothing re-reads Admits on a replay")
	_admits.reads.clear()
	# A replay carries no stream ([member AttackOutcome.crit_stream] null).
	await _drain(rebuilt.hits, null)
	assert_eq(_admits.reads.size(), 0, "a replay asks Admits nothing")
	assert_true(rebuilt.hits.any(func(h: HitInstance) -> bool: return h is DamageInstance and h.is_crit),
			"the recorded crit lands")
