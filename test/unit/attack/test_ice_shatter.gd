extends GutTest

## The shatter of a Frozen node ([FrozenAdmits] on the roster's Ice def): the
## spend to T, the burst through [method DotTick.mint] sized by the excess (the
## overflow included: deep freeze), the burst's added-excess input, a
## deep-frozen node answering as a Frozen one, and the read after the riders
## (a thaw is no breaker). The Cold addon's data closes the file.
##
## Copies come from a test [GoOff] on the roster's Lightning band, swapped in
## and restored. Every number reads the knobs.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _COLD_ADDON := "res://skill_node/addons/defs/cold_addon.tscn"


class _TestGoOff extends GoOff:
	func _init() -> void:
		void_floor = 0  # not about the pay rule

	var reach_of: Dictionary = {}

	func _reach(node: SkillNode, _read: TerrainRead) -> Array[GoOffResult.Reach]:
		var out: Array[GoOffResult.Reach] = []
		for n: SkillNode in reach_of.get(node, []):
			out.append(GoOffResult.Reach.new(n))
		return out


## The Ice answers with a test-supplied added excess at the burst's input.
class _AddedExcess extends FrozenAdmits:
	var x := 0.0

	func added_excess(_world: CombatWorld, _node: SkillNode, _arrivals: Array[Arrival]) -> float:
		return x


var _w: TestWorld
var _owner: Entity
var _attacker: Entity
var _h: SkillNode
var _f: SkillNode
var _g: SkillNode
var _ice: Element
var _fire: Element
var _light: Element
var _fa: FrozenAdmits
var _ice_admits: Array = []
var _spend_fraction := 1.0
var _light_bands: Array[ElementBand] = []
var _b: _TestGoOff
var _orig := 0


func before_each() -> void:
	CombatWorld.reset_live()
	_w = TestWorld.create(self)
	_owner = _entity()
	_attacker = _entity()
	await get_tree().process_frame
	_h = _w.add_node(&"H")
	_f = _w.add_node(&"F")
	_g = _w.add_node(&"G")
	_w.link(_h, _f)
	_w.link(_h, _g)
	_w.link(_f, _g)
	for n: SkillNode in [_h, _f, _g]:
		n.owned_by = _owner
	await get_tree().process_frame
	_ice = ElementRoster.shared().by_id(&"ice")
	_fire = ElementRoster.shared().by_id(&"fire")
	_light = ElementRoster.shared().by_id(&"lightning")
	_fa = _ice.bands[0].admits as FrozenAdmits
	_spend_fraction = _fa.shatter_spend_fraction
	_ice_admits = _ice.bands.map(func(b: ElementBand) -> Admits: return b.admits)
	_light_bands = _light.bands.duplicate()
	_b = _TestGoOff.new()
	var lband := ElementBand.new()
	lband.go_off = _b
	var lb: Array[ElementBand] = [lband]
	_light.bands = lb


func after_each() -> void:
	_fa.shatter_spend_fraction = _spend_fraction
	for i in _ice.bands.size():
		_ice.bands[i].admits = _ice_admits[i]
	_light.bands = _light_bands
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


func _cap(n: SkillNode) -> int:
	return _c(n).terrain_cap()


func _cold(n: SkillNode) -> int:
	return _c(n).terrain_count(_ice)


func _set_cold(n: SkillNode, k: int) -> void:
	_c(n).add_terrain(_fire, -k - _c(n).terrain_t())


func _max_hp(n: SkillNode) -> float:
	return _c(n).owner().get_max_hp()


func _tau(n: SkillNode) -> float:
	return _fa.break_fraction_max_hp * _max_hp(n)


func _burst_of(n: SkillNode, excess: float) -> float:
	return excess * _fa.shatter_fraction_per_stack * _max_hp(n)


func _pool(n: SkillNode) -> float:
	return (_c(n).owner().board().get_stat(&"health") as PoolStat).current


func _span(at: SkillNode, dmg: float, riders := {}) -> Array[HitInstance]:
	var d := DamageInstance.new()
	_stamp(d, at)
	d.amount = dmg
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	var span: Array[HitInstance] = [d]
	for def: StatusDef in riders:
		var s := StatusInstance.new()
		_stamp(s, at)
		s.def = def
		s.power = float(riders[def])
		s.raw = true
		span.append(s)
	return span


func _stamp(h: HitInstance, at: SkillNode) -> void:
	h.target = at
	h.attacker = _attacker
	h.schedule_index = 0
	h.structural_key = 0.0


func _crit(h: HitInstance, m := 1.5) -> void:
	h.is_crit = true
	h.crit_tier = 1
	h.crit_multiplier = m
	h.crit_decided = true


func _outcome(spans: Array) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	for span: Array in spans:
		for h: HitInstance in span:
			outcome.hits.append(h)
	_orig = outcome.hits.size()
	return outcome


func _gather(spans: Array) -> AttackOutcome:
	var outcome := _outcome(spans)
	HitGather.stage_one(outcome.hits.duplicate(), CombatWorld.live(), HitQueue.over(outcome.hits))
	return outcome


func _run(spans: Array) -> AttackOutcome:
	var outcome := _outcome(spans)
	await OutcomeApplier.drain(HitQueue.over(outcome.hits), CombatWorld.live(),
			BeatClock.instant_clock())
	return outcome


func _entries(outcome: AttackOutcome, at: SkillNode) -> Array:
	return outcome.hits.slice(_orig).filter(
			func(h: HitInstance) -> bool: return h.target == at and h.paired != null)


func _bursts(outcome: AttackOutcome) -> Array:
	return outcome.hits.slice(_orig).filter(func(h: HitInstance) -> bool: return h.paired == null) \
			.map(func(h: HitInstance) -> float: return h.amount)


## A direct crit on F at Cold [param cold]: the burst it pushes (−1 for none).
func _crit_burst(cold: int) -> float:
	_set_cold(_f, cold)
	var span := _span(_f, 1.0)
	_crit(span[0])
	var b := _bursts(_gather([span]))
	return float(b[0]) if b.size() == 1 else -1.0


## H primed on Lightning, its go-off reaching F only: the next hit on H sends F
## one copy.
func _copy_from_h() -> void:
	_c(_h).add_terrain(_light, _t(_h) + 1 - _c(_h).charge())
	_b.reach_of = {_h: [_f]}


# 4 ─────────────────────────────────────────────────────────────────────────────
func test_a_break_spends_to_T_and_bursts_the_excess_as_true_damage() -> void:
	var e := 4
	_set_cold(_f, _t(_f) + e)
	var pool := _pool(_f)
	var span := _span(_f, 1.0)
	_crit(span[0])
	await _run([span])
	assert_eq(_cold(_f), _t(_f), "the shatter leaves Cold at exactly T")
	assert_almost_eq(_pool(_f), pool - _burst_of(_f, e), 0.001,
			"the holder takes excess × fraction × max HP, TRUE, through DotTick.mint")

	_fa.shatter_spend_fraction = 0.5
	_set_cold(_f, _t(_f) + e)
	_crit_burst(_t(_f) + e)
	assert_eq(_cold(_f), _t(_f) + e - roundi(e * 0.5), "a lower fraction leaves T plus the unspent share")


func test_an_added_excess_raises_the_burst_and_leaves_the_spend() -> void:
	var added := _AddedExcess.new()
	added.x = 3.0
	for band in _ice.bands:
		band.admits = added
	var e := 2
	var b := _crit_burst(_t(_f) + e)
	assert_almost_eq(b, _burst_of(_f, e + added.x), 0.001, "(excess + x) × fraction × max HP")
	assert_eq(_cold(_f), _t(_f), "the spend reads the node's own excess: Cold still at T")


func test_an_unallocated_node_broken_by_a_crit_copy_loses_the_excess_and_takes_nothing() -> void:
	_copy_from_h()
	_f.owned_by = null
	_set_cold(_f, _t(_f) + 3)
	var span := _span(_h, 1.0)
	_crit(span[0])
	var out := _gather([span])
	assert_eq(_cold(_f), _t(_f), "the excess is spent")
	assert_eq(_bursts(out), [], "no DotTick.mint: no burst at all")


# 5 ─────────────────────────────────────────────────────────────────────────────
func test_deep_freeze_bursts_for_its_whole_excess_overflow_included() -> void:
	var deep := _cap(_f) + 3
	_set_cold(_f, deep)
	assert_eq(_cold(_f), deep, "fixture: the store holds past the cap")
	assert_eq(_c(_f).terrain_band(_ice), _ice.bands[_ice.bands.size() - 1], "fixture: the overflow band")
	var deep_burst := _crit_burst(deep)
	assert_eq(_cold(_f), _t(_f), "a deep freeze spends to T, overflow included")
	var shallow_burst := _crit_burst(_t(_f) + 1)
	assert_gt(deep_burst, shallow_burst, "a deep freeze bursts more than a shallow one")
	assert_almost_eq(deep_burst / shallow_burst, float(deep - _t(_f)) / 1.0, 0.001,
			"the ratio of the bursts is the ratio of the excesses")


# 5b ────────────────────────────────────────────────────────────────────────────
## The same arrivals on F at Cold [param cold]: an absorbed copy, a direct hit
## under τ, a crit direct hit. Everything but the burst.
func _answers(cold: int) -> Array:
	var tau := _tau(_f)
	_copy_from_h()
	_set_cold(_f, cold)
	var copy := _gather([_span(_h, tau * 0.5)])
	_set_cold(_f, cold)
	var under := _span(_f, tau * 0.5)
	var held := _gather([under])
	_set_cold(_f, cold)
	var crit := _span(_f, 1.0)
	_crit(crit[0])
	var broke := _gather([crit])
	return [_entries(copy, _f).size(), _bursts(copy).size(),
			_entries(held, _f).size(), under[0].path_ends,
			_entries(broke, _f).size(), crit[0].path_ends, _bursts(broke).size(), _cold(_f) - _t(_f)]


func test_a_deep_frozen_node_answers_exactly_as_a_frozen_one() -> void:
	var frozen := _answers(_t(_f) + 1)
	var deep := _answers(_cap(_f) + 1)
	assert_eq(frozen, [0, 0, 0, true, _fa.break_channels, false, 1, 0],
			"Frozen: copy absorbed; under τ ends the path; a crit breaks once")
	assert_eq(deep, frozen, "Deep freeze answers identically")


# 6 ─────────────────────────────────────────────────────────────────────────────
func test_the_breakers_and_the_path_end_read_the_band_after_the_riders() -> void:
	var tau := _tau(_f)
	var e := 2
	_set_cold(_f, _t(_f) + e)
	var thaw := _span(_f, 1.0, {_fire.terrain: e})
	_crit(thaw[0])
	var out := _gather([thaw])
	assert_eq(_entries(out, _f).size(), 0, "a hit whose own Heat thaws the node: no extra landing")
	assert_eq(_bursts(out), [], "no shatter, no burst")
	assert_false(thaw[0].path_ends, "and its walk goes on")
	assert_eq(_cold(_f), _t(_f), "the Heat landed (T or below)")

	_set_cold(_f, _t(_f))
	var freeze := _span(_f, tau * 0.5, {_ice.terrain: 1})
	_gather([freeze])
	assert_true(freeze[0].path_ends, "a hit whose own Cold takes it over T ends its walk there")

	_set_cold(_f, _t(_f))
	var freeze_crit := _span(_f, 1.0, {_ice.terrain: 1})
	_crit(freeze_crit[0])
	out = _gather([freeze_crit])
	assert_eq(_entries(out, _f).size(), _fa.break_channels, "with a crit it shatters at once")
	assert_eq(_bursts(out).size(), 1, "one burst")
	assert_false(freeze_crit[0].path_ends, "and its walk goes on")

	_copy_from_h()
	_set_cold(_f, _t(_f) + e)
	out = _gather([_span(_h, tau * 0.5, {_fire.terrain: e})])
	assert_eq(_cold(_f), _t(_f), "an absorbed copy's Heat thaws F")
	assert_eq(_entries(out, _f).size(), 0, "its damage and aspect riders still do not land")
	assert_eq(_bursts(out), [], "no shatter, no burst")


# Cold addon ─────────────────────────────────────────────────────────────────────
func test_the_cold_addon_rides_cold_at_power_one_and_changes_no_stat() -> void:
	var scene := load(_COLD_ADDON) as PackedScene
	assert_not_null(scene, "cold_addon.tscn exists")
	if scene == null:
		return
	var addon := scene.instantiate() as SkillNodeAddon
	var riders := addon.on_hit_effects.filter(func(x: OnHitEffect) -> bool: return x is ApplyStatusEffect)
	assert_eq(riders.size(), 1, "one rider")
	assert_eq(addon.on_hit_effects.size(), 1, "and nothing else on hit")
	if riders.size() == 1:
		assert_eq((riders[0] as ApplyStatusEffect).def, _ice.terrain, "the rider is Ice's terrain, Cold")
		assert_eq(roundi((riders[0] as ApplyStatusEffect).power), 1, "at power 1")
	assert_eq([addon.entity_modifiers.size(), addon.local_modifiers.size(), addon.effects.size()],
			[0, 0, 0], "no stat, no effect")
	assert_eq(addon.temp_cost_aspects, {&"ice_element": 1} as Dictionary[StringName, int],
			"costs 1 of the ice_element count")
	addon.queue_free()
