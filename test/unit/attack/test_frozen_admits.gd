extends GutTest

## Ice's answers on a Frozen node ([FrozenAdmits], set on both Ice bands of the
## roster's own Ice def), through [HitGather]'s two seams: the admit on arrival
## (a copy under the flat breaker with no crit is absorbed, its terrain riders
## still land) and the read after the riders (each arrival tested alone for a
## break; a break takes `break_channels` extra landings per breaker, one spend
## and one burst; else paths end at the node).
##
## Copies come from a test [GoOff] on the roster's Lightning band (Charge, an
## axis apart from Cold) and, for the whole hit, a second on Fire's band. Both
## are swapped in before each test and restored after; Ice is the real def.
## Every threshold reads the knobs: τ = `break_fraction_max_hp` × the holder's
## max HP.

const _POISON := preload("res://effects/status/poison.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")


## A test go-off: reaches what [member reach_of] names for the node it fires
## on, through the base law, and adds [member own_damage] to each copy.
class _TestGoOff extends GoOff:
	var reach_of: Dictionary = {}
	var own_damage := 0.0

	func fire(node: SkillNode, read: TerrainRead) -> GoOffResult:
		var r := super(node, read)
		r.own_damage = own_damage
		return r

	func _reach(node: SkillNode, _read: TerrainRead) -> Array[GoOffResult.Reach]:
		var out: Array[GoOffResult.Reach] = []
		for n: SkillNode in reach_of.get(node, []):
			out.append(GoOffResult.Reach.new(n))
		return out


var _w: TestWorld
var _owner: Entity
var _attacker: Entity
var _h: SkillNode
var _f: SkillNode
var _n2: SkillNode
var _n3: SkillNode
var _ice: Element
var _fire: Element
var _light: Element
var _fa: FrozenAdmits
var _fire_bands: Array[ElementBand] = []
var _light_bands: Array[ElementBand] = []
var _a: _TestGoOff
var _b: _TestGoOff
var _orig := 0
var _mods: Array = []  # [NodeCombat, StatModifier]


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_owner = _entity()
	_attacker = _entity()
	await get_tree().process_frame
	_h = _w.add_node(&"H")
	_f = _w.add_node(&"F")
	_n2 = _w.add_node(&"N2")
	_n3 = _w.add_node(&"N3")
	for n: SkillNode in [_f, _n2, _n3]:
		_w.link(_h, n)
	_w.link(_f, _n2)
	for n: SkillNode in [_h, _f, _n2, _n3]:
		n.owned_by = _owner
	await get_tree().process_frame
	_ice = ElementRoster.shared().by_id(&"ice")
	_fire = ElementRoster.shared().by_id(&"fire")
	_light = ElementRoster.shared().by_id(&"lightning")
	_fa = _ice.bands[0].admits as FrozenAdmits
	_fire_bands = _fire.bands.duplicate()
	_light_bands = _light.bands.duplicate()
	_a = _TestGoOff.new()
	var fband := ElementBand.new()
	fband.go_off = _a
	var fb: Array[ElementBand] = [fband]
	_fire.bands = fb
	_b = _TestGoOff.new()
	var lband := ElementBand.new()
	lband.go_off = _b
	var lb: Array[ElementBand] = [lband]
	_light.bands = lb
	_mods = []


func after_each() -> void:
	for m: Array in _mods:
		(m[0] as NodeCombat).remove_local_modifier(m[1])
	_fire.bands = _fire_bands
	_light.bands = _light_bands
	HitGather.tunables = HitGather.DEFAULT_TUNABLES
	CombatWorld.reset_live()


func _entity() -> Entity:
	var e := Entity.new()
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_w.graph.add_child(e)
	return e


func _c(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n)


func _t(n: SkillNode) -> int:
	return _c(n).terrain_threshold()


func _cold(n: SkillNode) -> int:
	return _c(n).terrain_count(_ice)


## [param n]'s Cold set to [param k] (the shared Heat/Cold axis at −k).
func _set_cold(n: SkillNode, k: int) -> void:
	_c(n).add_terrain(_fire, -k - _c(n).terrain_t())


func _set_heat(n: SkillNode, k: int) -> void:
	_c(n).add_terrain(_fire, k - _c(n).terrain_t())


func _set_charge(n: SkillNode, k: int) -> void:
	_c(n).add_terrain(_light, k - _c(n).charge())


func _max_hp(n: SkillNode) -> float:
	return _c(n).owner().get_max_hp()


## τ: the flat breaker on [param n]'s holder.
func _tau(n: SkillNode) -> float:
	return _fa.break_fraction_max_hp * _max_hp(n)


func _burst_of(n: SkillNode, excess: float) -> float:
	return excess * _fa.shatter_fraction_per_stack * _max_hp(n)


func _mod(n: SkillNode, id: StringName, value: float) -> void:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	_c(n).add_local_modifier(m)
	_mods.append([_c(n), m])


## One hit on [param at]: a damage head of [param dmg], then its riders,
## `{StatusDef: power}` (Cold, Heat, Poison) in that order.
func _span(at: SkillNode, dmg: float, riders := {}, type := DamageInstance.Type.TRUE,
		si := 0) -> Array[HitInstance]:
	var d := DamageInstance.new()
	_stamp(d, at, si)
	d.amount = dmg
	d.type = type
	d.is_head = true
	var span: Array[HitInstance] = [d]
	for def: StatusDef in riders:
		var s := StatusInstance.new()
		_stamp(s, at, si)
		s.def = def
		s.power = float(riders[def])
		s.raw = true
		span.append(s)
	return span


func _stamp(h: HitInstance, at: SkillNode, si: int) -> void:
	h.target = at
	h.attacker = _attacker
	h.schedule_index = si
	h.structural_key = float(si)


## A crit already decided on [param h] (the head), at multiplier [param m].
func _crit(h: HitInstance, m := 1.5) -> void:
	h.is_crit = true
	h.crit_tier = 1
	h.crit_multiplier = m
	h.crit_decided = true


## Stage one alone, on the live world: nothing lands but the element riders.
func _gather(spans: Array) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	for span: Array in spans:
		for h: HitInstance in span:
			outcome.hits.append(h)
	_orig = outcome.hits.size()
	HitGather.stage_one(outcome.hits.duplicate(), CombatWorld.live(), HitQueue.over(outcome.hits))
	return outcome


## Stage two's entries on [param at]: the pushed copies, each paired to its head.
func _entries(outcome: AttackOutcome, at: SkillNode) -> Array:
	return outcome.hits.slice(_orig).filter(
			func(h: HitInstance) -> bool: return h.target == at and h.paired != null)


func _damage(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is DamageInstance) \
			.map(func(h: HitInstance) -> float: return h.amount)


func _poison(hits: Array) -> Array:
	return hits.filter(func(h: HitInstance) -> bool: return h is StatusInstance and h.def == _POISON)


## The bursts stage one pushed: unpaired damage past the authored hits.
func _bursts(outcome: AttackOutcome) -> Array:
	return outcome.hits.slice(_orig).filter(func(h: HitInstance) -> bool: return h.paired == null) \
			.map(func(h: HitInstance) -> float: return h.amount)


## H primed on Lightning, its go-off reaching F only: the next hit on H sends F
## one copy, carrying the hit's terrain riders. The go-off spends H's Charge:
## re-prime before each gather.
func _copy_from_h() -> void:
	_set_charge(_h, _t(_h) + 1)
	_b.reach_of = {_h: [_f]}


# 1 ─────────────────────────────────────────────────────────────────────────────
func test_a_copy_under_the_breaker_is_absorbed_and_lands_its_terrain() -> void:
	assert_not_null(_fa, "both Ice bands carry a FrozenAdmits")
	_copy_from_h()
	var tau := _tau(_f)
	var cold := _t(_f) + 2
	_set_cold(_f, cold)
	var out := _gather([_span(_h, tau * 0.5, {_ice.terrain: 3, _POISON: 2})])
	assert_eq(_entries(out, _f).size(), 0, "no entry on F: no damage, no aspect rider")
	assert_eq(_cold(_f), cold + 3, "its Cold lands all the same")
	assert_eq(_bursts(out), [], "and no burst")

	_copy_from_h()
	_set_cold(_f, cold)
	out = _gather([_span(_h, tau * 0.5, {_fire.terrain: 1, _POISON: 2})])
	assert_eq(_entries(out, _f).size(), 0, "a Heat copy is absorbed as well")
	assert_eq(_cold(_f), cold - 1, "its Heat lands: T + e − h, still Frozen")


# 2 ─────────────────────────────────────────────────────────────────────────────
func test_a_direct_hit_under_the_breaker_lands_once_and_breaks_nothing() -> void:
	var tau := _tau(_f)
	var cold := _t(_f) + 2
	_set_cold(_f, cold)
	var span := _span(_f, tau * 0.5, {_ice.terrain: 2})
	var out := _gather([span])
	assert_eq(_entries(out, _f).size(), 0, "the head is its only landing")
	assert_eq(_bursts(out), [], "no burst")
	assert_eq(_cold(_f), cold + 2, "its Cold deepens the freeze")
	assert_true(span[0].path_ends, "and its path ends at F")

	_copy_from_h()
	_set_cold(_f, cold)
	_gather([_span(_h, tau * 0.5, {_ice.terrain: 2})])
	assert_eq(_cold(_f), cold + 2, "an absorbed copy's Cold deepens it the same")


# 3 ─────────────────────────────────────────────────────────────────────────────
func test_a_copy_at_the_breaker_or_a_crit_copy_breaks_the_ice() -> void:
	_copy_from_h()
	var tau := _tau(_f)
	var e := 3
	_set_cold(_f, _t(_f) + e)
	var out := _gather([_span(_h, tau * 1.5, {_POISON: 1})])
	var n := 1 + _fa.break_channels
	assert_eq(_damage(_entries(out, _f)).size(), n, "1 + break_channels landings of D")
	assert_eq(_cold(_f), _t(_f), "the shatter spends to T")
	assert_almost_eq(float(_bursts(out)[0]) if _bursts(out).size() == 1 else -1.0,
			_burst_of(_f, e), 0.001, "one burst of excess × fraction × M")

	_copy_from_h()
	_set_cold(_f, _t(_f) + e)
	var span := _span(_h, tau * 0.4)
	_crit(span[0], 1.5)
	out = _gather([span])
	assert_eq(_damage(_entries(out, _f)).size(), n, "a crit copy under τ breaks it too")
	assert_eq(_cold(_f), _t(_f), "and spends to T")


func test_the_damage_breaker_reads_the_mitigated_number() -> void:
	_copy_from_h()
	var tau := _tau(_f)
	var floor0 := float(_c(_f).get_local_value(&"min_damage_taken"))
	var armor := tau * 0.5
	assert_lt(floor0, tau - armor * 0.5, "fixture: the board's floor sits under D − a")
	_mod(_f, &"armor", armor)
	var d := tau + armor * 0.5  # D − a < τ ≤ D
	_set_cold(_f, _t(_f) + 2)
	var out := _gather([_span(_h, d, {}, DamageInstance.Type.PHYSICAL)])
	assert_eq(_entries(out, _f).size(), 0, "D − a < τ: absorbed")
	assert_eq(_cold(_f), _t(_f) + 2, "no break")

	_copy_from_h()
	_mod(_f, &"min_damage_taken", tau)
	out = _gather([_span(_h, d, {}, DamageInstance.Type.PHYSICAL)])
	assert_eq(_damage(_entries(out, _f)).size(), 1 + _fa.break_channels, "the floor ≥ τ breaks it")
	assert_eq(_cold(_f), _t(_f), "spent to T")


func test_an_unallocated_frozen_node_breaks_only_by_a_crit() -> void:
	_copy_from_h()
	var tau := _tau(_h)
	_f.owned_by = null
	var cold := _t(_f) + 2
	_set_cold(_f, cold)
	var out := _gather([_span(_h, tau * 100.0, {_ice.terrain: 1})])
	assert_eq(_entries(out, _f).size(), 0, "no holder, no flat breaker: absorbed whatever its damage")
	assert_eq(_cold(_f), cold + 1, "its terrain riders still land")

	_copy_from_h()
	_set_cold(_f, cold)
	var span := _span(_h, 1.0)
	_crit(span[0])
	out = _gather([span])
	assert_eq(_cold(_f), _t(_f), "a crit copy breaks it: Cold at T")
	assert_eq(_bursts(out), [], "and no burst on an unallocated node")


# 3b ────────────────────────────────────────────────────────────────────────────
## H in Fire's band (A) and Lightning's (B), each go-off reaching F only; F at
## Cold T + 4. The hit on H carries [param d], Poison [param r] and Heat 1.
func _whole(d: float, crit: bool, a_own := 0.0, r := 2) -> AttackOutcome:
	_set_heat(_h, _t(_h) + 1)
	_set_charge(_h, _t(_h) + 1)
	_a.reach_of = {_h: [_f]}
	_b.reach_of = {_h: [_f]}
	_a.own_damage = a_own
	_set_cold(_f, _t(_f) + 4)
	var span := _span(_h, d, {_fire.terrain: 1, _POISON: r})
	if crit:
		_crit(span[0])
	return _gather([span])


func test_the_whole_hit_at_a_frozen_node_absorbs_or_breaks_each_copy_alone() -> void:
	var tau := _tau(_f)
	var n := 1 + _fa.break_channels
	var out := _whole(tau * 0.5, false)
	assert_eq(_entries(out, _h).size(), 2 * 2, "H takes 3: its own and a centre copy per channel")
	assert_eq(_entries(out, _f).size(), 0, "both copies absorbed")
	assert_eq(_cold(_f), _t(_f) + 3, "the Heat lands on F once")
	assert_eq(_bursts(out), [], "no burst")

	for crit in [false, true]:
		out = _whole(tau * (0.4 if crit else 1.5), crit)
		var on_f := _entries(out, _f)
		assert_eq(_damage(on_f).size(), 2 * n, "both break, each with its own extras (crit %s)" % crit)
		assert_eq(_poison(on_f).size(), 2 * n, "each landing carries the aspect rider (crit %s)" % crit)
		assert_eq(_cold(_f), _t(_f), "one shatter to T (crit %s)" % crit)
		assert_eq(_bursts(out).size(), 1, "one burst (crit %s)" % crit)
		if _bursts(out).size() == 1:
			assert_almost_eq(float(_bursts(out)[0]), _burst_of(_f, 3), 0.001,
					"of the excess after the Heat: 3 (crit %s)" % crit)


func test_a_sibling_under_the_breaker_stays_absorbed_when_the_other_breaks() -> void:
	var tau := _tau(_f)
	var n := 1 + _fa.break_channels
	var d := tau * 0.6
	var results: Array = []
	for a_breaks in [true, false]:
		var out: AttackOutcome
		if a_breaks:
			out = _whole(d, false, tau * 0.6)
		else:
			# Swapped: B's copy carries the own damage.
			_b.own_damage = tau * 0.6
			out = _whole(d, false, 0.0)
			_b.own_damage = 0.0
		var dmg := _damage(_entries(out, _f))
		assert_eq(dmg.size(), n, "only the breaker lands, 1 + break_channels times")
		for x in dmg:
			assert_almost_eq(float(x), d + tau * 0.6, 0.001, "each the breaker's D + d")
		results.append([dmg.size(), _cold(_f), _bursts(out)])
	assert_eq(results[0], results[1], "swapping A and B changes nothing")
	assert_eq(results[0][1], _t(_f), "one shatter to T")
	assert_eq((results[0][2] as Array).size(), 1, "one burst")


func test_a_direct_crit_on_a_frozen_node_takes_its_extras_and_one_burst() -> void:
	_set_cold(_f, _t(_f) + 2)
	var span := _span(_f, 1.0)
	_crit(span[0])
	var out := _gather([span])
	assert_eq(_damage(_entries(out, _f)).size(), _fa.break_channels, "the head + break_channels")
	assert_eq(_bursts(out).size(), 1, "one burst")
	assert_false(span[0].path_ends, "a break walks on")


func test_a_merged_dual_reach_is_one_arrival_at_its_summed_amount() -> void:
	var tau := _tau(_f)
	var tun := HitGatherTunables.new()
	tun.dedupe_dual_reach = true
	HitGather.tunables = tun
	var out := _whole(tau * 0.6, false)  # D < τ ≤ 2D
	assert_eq(_cold(_f), _t(_f), "the merged 2D breaks the ice")
	assert_eq(_bursts(out).size(), 1, "one burst")
	HitGather.tunables = HitGather.DEFAULT_TUNABLES
	out = _whole(tau * 0.6, false)
	assert_eq(_entries(out, _f).size(), 0, "off: two copies of D, each absorbed")
	assert_eq(_cold(_f), _t(_f) + 3, "no break")


# 3c ────────────────────────────────────────────────────────────────────────────
func test_one_generation_settles_two_direct_hits_once() -> void:
	var tau := _tau(_f)
	for order in [0, 1]:
		_set_cold(_f, _t(_f) + 2)
		var p := _span(_f, tau * 0.4)
		_crit(p[0])
		var q := _span(_f, tau * 0.5)
		var out := _gather([p, q] if order == 0 else [q, p])
		var by := func(head: HitInstance) -> int:
			return _entries(out, _f).filter(func(h: HitInstance) -> bool: return h.paired == head).size()
		assert_eq(by.call(p[0]), _fa.break_channels, "P takes 1 + break_channels (order %d)" % order)
		assert_eq(by.call(q[0]), 0, "Q takes one (order %d)" % order)
		assert_eq(_cold(_f), _t(_f), "one shatter (order %d)" % order)
		assert_eq(_bursts(out).size(), 1, "one burst (order %d)" % order)
		assert_false(p[0].path_ends or q[0].path_ends, "neither path ends (order %d)" % order)

	_set_cold(_f, _t(_f) + 2)
	var p2 := _span(_f, tau * 0.4)
	var q2 := _span(_f, tau * 0.5)
	var out2 := _gather([p2, q2])
	assert_eq(_entries(out2, _f).size(), 0, "neither breaks: one landing each")
	assert_eq(_bursts(out2), [], "no burst")
	assert_true(p2[0].path_ends and q2[0].path_ends, "both paths end")


# 7 ─────────────────────────────────────────────────────────────────────────────
## The walk N3 → H → F, N2 with H Frozen: a hop under τ ends the walk there; a
## hop that breaks H walks on.
func test_a_spell_walk_ends_at_a_frozen_node_unless_the_hop_breaks_it() -> void:
	_light.bands = _light_bands
	_fire.bands = _fire_bands
	# No crit: a crit on the light hop would break the ice by itself.
	_attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var helper := SpellTestHelper.new()
	var walk := func(power: float) -> Dictionary:
		_set_cold(_h, _t(_h) + 1)
		var spell := helper.make_spell(helper.make_config(helper.fan_all(), null, null, {max_hops = 2}),
				[DamageEffect.new()] as Array[OnHitEffect], power)
		var out := SpellResolver.resolve_against(spell, _n3, null, _attacker, _w.graph, CombatWorld.live())
		var by := {}
		for ev: PropagationEvent in out.timeline:
			by[ev.target] = ev
		return by
	var held: Dictionary = walk.call(0.01)
	assert_true(held.has(_h) and held[_h].is_terminal, "under τ: the middle landing is terminal")
	assert_false(held.has(_f) or held.has(_n2), "and no next wave is minted past it")
	assert_lt(_t(_h), _cold(_h), "the ice holds")
	var broke: Dictionary = walk.call(_tau(_h) * 100.0)
	assert_true(broke.has(_f) and broke.has(_n2), "a hop that breaks the ice walks on")
	assert_eq(_cold(_h), _t(_h), "and shatters it to T")
