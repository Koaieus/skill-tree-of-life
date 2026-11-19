extends GutTest

## The Ice cues ([member HitInstance.ice_cues]): the gather's read/shatter loop
## records a break (node + excess) and a hold (an absorbed copy or an ended
## walk) on the beat's first head; the record ships them; [method
## OutcomeApplier.land_one] announces them on a live world only.
##
## Copies come from a test [GoOff] on the roster's Lightning band, swapped in
## and restored, as in test_ice_shatter.gd.

const _BOARD := preload("res://entity/default_entity_board.tres")


class _TestGoOff extends GoOff:
	var reach_of: Dictionary = {}

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
var _g: SkillNode
var _fire: Element
var _light: Element
var _fa: FrozenAdmits
var _light_bands: Array[ElementBand] = []
var _b: _TestGoOff
var _shadow: CombatWorld


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
	var ice := ElementRoster.shared().by_id(&"ice")
	_fire = ElementRoster.shared().by_id(&"fire")
	_light = ElementRoster.shared().by_id(&"lightning")
	_fa = ice.bands[0].admits as FrozenAdmits
	_light_bands = _light.bands.duplicate()
	_b = _TestGoOff.new()
	var lband := ElementBand.new()
	lband.go_off = _b
	var lb: Array[ElementBand] = [lband]
	_light.bands = lb


func after_each() -> void:
	_light.bands = _light_bands
	if _shadow != null:
		_shadow.free_shadow()
		_shadow = null
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


func _set_cold(n: SkillNode, k: int) -> void:
	_c(n).add_terrain(_fire, -k - _c(n).terrain_t())


func _span(at: SkillNode, dmg: float, crit := false) -> Array[HitInstance]:
	var d := DamageInstance.new()
	d.target = at
	d.attacker = _attacker
	d.amount = dmg
	d.type = DamageInstance.Type.TRUE
	d.is_head = true
	if crit:
		d.is_crit = true
		d.crit_tier = 1
		d.crit_multiplier = 1.5
		d.crit_decided = true
	var span: Array[HitInstance] = [d]
	return span


func _gather(span: Array[HitInstance]) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.hits.append_array(span)
	HitGather.stage_one(outcome.hits.duplicate(), CombatWorld.live(), HitQueue.over(outcome.hits))
	return outcome


## Every cue the outcome's hits carry, in hit order.
func _cues(outcome: AttackOutcome) -> Array:
	var out: Array = []
	for h in outcome.hits:
		out.append_array(h.ice_cues)
	return out


func _copy_from_h() -> void:
	_c(_h).add_terrain(_light, _t(_h) + 1 - _c(_h).charge())
	_b.reach_of = {_h: [_f]}


func test_a_break_cues_its_node_and_excess_on_the_head() -> void:
	_set_cold(_f, _t(_f) + 4)
	var span := _span(_f, 1.0, true)
	var out := _gather(span)
	assert_eq(span[0].ice_cues, [[_f, 4]], "the head carries F's break at excess 4")
	assert_eq(_cues(out).size(), 1, "and nothing else carries one")


func test_a_deep_freeze_cues_a_bigger_excess_than_a_shallow_one() -> void:
	_set_cold(_f, _t(_f) + 1)
	var shallow := _span(_f, 1.0, true)
	_gather(shallow)
	_set_cold(_f, _t(_f) + 6)
	var deep := _span(_f, 1.0, true)
	_gather(deep)
	assert_eq(shallow[0].ice_cues, [[_f, 1]])
	assert_eq(deep[0].ice_cues, [[_f, 6]])


func test_an_unallocated_node_broken_by_a_crit_copy_still_cues_the_break() -> void:
	_copy_from_h()
	_f.owned_by = null
	_set_cold(_f, _t(_f) + 3)
	var span := _span(_h, 1.0, true)
	_gather(span)
	assert_eq(span[0].ice_cues, [[_f, 3]], "no burst, but the break shows")


func test_an_absorbed_copy_cues_a_hold_once() -> void:
	_copy_from_h()
	_set_cold(_f, _t(_f) + 2)
	var span := _span(_h, 0.01)
	var out := _gather(span)
	assert_eq(span[0].ice_cues, [[_f, HitInstance.ICE_HELD]], "F held the copy")
	assert_eq(_cues(out).size(), 1, "one hold for F, none for unfrozen H")


func test_an_unfrozen_beat_cues_nothing() -> void:
	_copy_from_h()
	var out := _gather(_span(_h, 1.0, true))
	assert_eq(_cues(out), [])


func test_the_cues_ride_the_record() -> void:
	_set_cold(_f, _t(_f) + 4)
	_copy_from_h()
	_b.reach_of = {_h: [_f, _g]}
	_set_cold(_g, _t(_g) + 2)
	var span := _span(_h, 0.01, true)
	var out := _gather(span)
	var sent := _cues(out)
	assert_eq(sent.size(), 2, "both F and G broke")
	var back := AttackRecord.rebuild(AttackRecord.capture(out, _w.graph), _w.graph)
	assert_eq(_cues(back), sent, "the rebuilt beat carries the same cues, in order")


func test_a_record_without_cues_ships_no_cue_column() -> void:
	var out := _gather(_span(_h, 1.0))
	var d := AttackRecord.capture(out, _w.graph)
	for key: String in d:
		assert_false(key.begins_with("ic_"), "no cue key %s on a cue-less record" % key)


func _carrier(staged: bool) -> HitInstance:
	var d := DamageInstance.new()
	d.target = _h
	d.attacker = _attacker
	d.amount = 0.0
	d.staged = staged
	d.ice_cues = [[_f, 5], [_g, HitInstance.ICE_HELD]]
	return d


func test_land_one_announces_each_cue_on_a_live_world() -> void:
	watch_signals(Events)
	OutcomeApplier.land_one(_carrier(true), CombatWorld.live())
	assert_signal_emitted_with_parameters(Events, "ice_shattered", [_f, 5, _attacker])
	assert_signal_emitted_with_parameters(Events, "ice_held", [_g, _attacker])
	assert_signal_emit_count(Events, "ice_shattered", 1)
	assert_signal_emit_count(Events, "ice_held", 1)


func test_land_one_on_a_shadow_world_announces_nothing() -> void:
	_shadow = CombatWorld.shadow()
	watch_signals(Events)
	OutcomeApplier.land_one(_carrier(false), _shadow)
	assert_signal_emit_count(Events, "ice_shattered", 0)
	assert_signal_emit_count(Events, "ice_held", 0)


func test_a_freed_cue_node_is_skipped() -> void:
	var hit := _carrier(false)
	_g.free()
	watch_signals(Events)
	OutcomeApplier.land_one(hit, CombatWorld.live())
	assert_signal_emit_count(Events, "ice_shattered", 1)
	assert_signal_emit_count(Events, "ice_held", 0)
