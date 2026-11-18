extends GutTest

## The sweep factor (#1804): a contact's speed is scaled by
## `clamp(1 + c·t/T, 1−c, 1+c)` of the node it lands on before the speed curve
## reads it — Cold slows, Heat speeds, never past `1 ± c`, `t = 0` exactly 1 —
## and the raw amount (coefficient × curve) is stamped on the head as its beat's
## gather opens, on the gather's world, before armor.
##
## Board: VolleyBoardFixture — target (450,0) hostile; the attacker owns the
## hub and the leaves.

const _M := 3.0
const _V_HALF := 400.0
const _C := 0.4
const _K := 10.0
const _V := 600.0


## Records each arrival's amount at the node's second read.
class _Recorder:
	extends Admits
	var amounts: Array[float] = []

	func read(_node: SkillNode, _after: TerrainRead, arrivals: Array[Arrival]) -> AdmitsAnswer:
		for a in arrivals:
			if not a.is_copy:
				amounts.append(a.amount)
		return AdmitsAnswer.new()


var _f: VolleyBoardFixture
var _held: Array = []  # [band, admits, go_off]


func after_each() -> void:
	if not _held.is_empty():
		var band: ElementBand = _held[0]
		band.admits = _held[1]
		band.go_off = _held[2]
		_held = []
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0
	var board := _f.attacker.stat_board
	board.blade_speed_multiplier_max.base_value = _M
	board.blade_speed_half.base_value = _V_HALF
	board.blade_temperature_speed.base_value = _C
	board.crit_chance.base_value = 0.0


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


## The target sits in Lightning's band (Charge at T, independent of t), its
## second read recorded and its go-off silenced (both put back after).
func _record() -> _Recorder:
	var lightning := ElementRoster.shared().by_id(&"lightning")
	var band: ElementBand = lightning.bands[0]
	var rec := _Recorder.new()
	_held = [band, band.admits, band.go_off]
	band.admits = rec
	band.go_off = null
	var c := _f.target.get_combat()
	c.add_terrain(lightning, c.terrain_threshold() * band.threshold_multiple + 1 - c.charge())
	return rec


func _set_t(t: int) -> void:
	var c := _f.target.get_combat()
	c.add_terrain(_fire(), t - c.terrain_t())
	assert_eq(c.terrain_t(), t, "fixture: the target's t")


func _threshold() -> int:
	return _f.target.get_combat().terrain_threshold()


func _expected(t: int) -> float:
	var factor := clampf(1.0 + _C * float(t) / float(_threshold()), 1.0 - _C, 1.0 + _C)
	return _K * BladeState.speed_damage_multiplier(_V * factor, _M, _V_HALF)


func _contact(hits: Array[HitInstance]) -> BladeDamageInstance:
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0]]
	BladeVertexFill.new().fill(s, nodes)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var ev := BladeHitEvent.new(0.5, 1, -1, _f.target)
	ev.speed = _V
	var di := BladeDamageInstance.new(ev, gate)
	di.amount = _K
	di.type = DamageInstance.Type.PHYSICAL
	di.target = _f.target
	di.attacker = _f.attacker
	hits.append(di)
	var landing := HitLanding.riding(di, hits)
	landing.target_mask = SkillNode.Ownership.HOSTILE
	landing.place()
	return di


func _land(hits: Array[HitInstance]) -> void:
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())


# --- the factor --------------------------------------------------------------------

func test_cold_slows_heat_speeds_and_t_zero_is_exactly_one() -> void:
	assert_eq(BladeState.temperature_speed_factor(0, 4, 0.5), 1.0, "t = 0: exactly 1")
	assert_lt(BladeState.temperature_speed_factor(-2, 4, 0.5), 1.0, "Cold lowers")
	assert_gt(BladeState.temperature_speed_factor(2, 4, 0.5), 1.0, "Heat raises")


func test_the_factor_never_leaves_one_plus_minus_c() -> void:
	for t in [-1000, -9, -4, -1, 1, 4, 9, 1000]:
		var f := BladeState.temperature_speed_factor(t, 4, 0.5)
		assert_between(f, 0.5, 1.5, "t = %d stays in [1 − c, 1 + c]" % t)


func test_a_contact_on_cold_lands_less_and_on_heat_more() -> void:
	var curve := func(t: int) -> float:
		return BladeDamageInstance.contact_multiplier(null, _V, t, 4)
	assert_eq(curve.call(0), BladeState.speed_damage_multiplier(_V, 1.0, 0.0), "boardless: today's")
	var board := (load("res://entity/default_entity_board.tres") as EntityStatBoard).duplicate(true) as EntityStatBoard
	var wielder := Entity.new()
	wielder.stat_board = board
	var zero := BladeDamageInstance.contact_multiplier(wielder, _V, 0, 4)
	assert_lt(BladeDamageInstance.contact_multiplier(wielder, _V, -2, 4), zero, "Cold lands less")
	assert_gt(BladeDamageInstance.contact_multiplier(wielder, _V, 2, 4), zero, "Heat lands more")
	var m := BladeState.stat_value(board, &"blade_speed_multiplier_max", 1.0)
	var v_half := BladeState.stat_value(board, &"blade_speed_half", 0.0)
	assert_eq(zero, BladeState.speed_damage_multiplier(_V, m, v_half), "t = 0 is bit-identical to today")
	wielder.free()


# --- 6b: the raw amount -------------------------------------------------------------

func test_the_gather_reads_the_raw_amount_at_a_signed_t() -> void:
	await _board()
	assert_gt(_threshold(), 1, "fixture: T leaves room for 0 < |t| < T")
	var rec := _record()
	_set_t(1)
	var hits: Array[HitInstance] = []
	_contact(hits)
	await _land(hits)
	assert_eq(rec.amounts.size(), 1, "the contact reached the second read")
	assert_almost_eq(rec.amounts[0], _expected(1), 0.0001, "k × curve(v × factor(t))")
	assert_gt(_expected(1), _expected(0), "fixture: Heat moved the number")


func test_at_t_zero_the_raw_amount_is_todays_curve() -> void:
	await _board()
	var rec := _record()
	_set_t(0)
	var hits: Array[HitInstance] = []
	_contact(hits)
	await _land(hits)
	assert_almost_eq(rec.amounts[0], _K * BladeState.speed_damage_multiplier(_V, _M, _V_HALF), 0.0001,
			"t = 0: k × curve(v)")


func test_armor_leaves_the_stamp_and_zero_armor_takes_it_once() -> void:
	await _board()
	var rec := _record()
	_set_t(-1)
	_f.hostile.stat_board.armor.base_value = 0.0
	_f.hostile.stat_board.min_damage_taken.base_value = 0.0
	var hp := _f.target.get_combat().get_current_hp()
	var hits: Array[HitInstance] = []
	_contact(hits)
	await _land(hits)
	assert_almost_eq(hp - _f.target.get_combat().get_current_hp(), HitPoints.whole(_expected(-1)), 0.0001,
			"zero armor: the HP taken is the stamp in whole HP (the curve ran once)")
	var taken := hp - _f.target.get_combat().get_current_hp()
	_f.hostile.stat_board.armor.base_value = 5.0
	var before := _f.target.get_combat().get_current_hp()
	var armored: Array[HitInstance] = []
	_contact(armored)
	await _land(armored)
	assert_lt(before - _f.target.get_combat().get_current_hp(), taken, "fixture: the armor bit")
	assert_almost_eq(rec.amounts[1], rec.amounts[0], 0.0001, "armor leaves the stamped number unchanged")


func test_the_stamp_reads_the_gathers_world_not_the_mints() -> void:
	await _board()
	var rec := _record()
	_set_t(0)
	var hits: Array[HitInstance] = []
	_contact(hits)
	_set_t(-1)
	await _land(hits)
	assert_almost_eq(rec.amounts[0], _expected(-1), 0.0001, "the later t's raw amount")


func test_the_authority_amount_and_the_cosmetic_floater_agree() -> void:
	await _board()
	var rec := _record()
	_set_t(1)
	var hits: Array[HitInstance] = []
	var di := _contact(hits)
	await _land(hits)
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	blade.owned_by = _f.attacker
	assert_almost_eq(_K * blade._speed_multiplier(di._event), rec.amounts[0], 0.0001,
			"the floater's curve is the stamp's")


func test_the_stamp_writes_the_sweep_factor_the_floater_cues_on() -> void:
	await _board()
	_record()
	for t in [1, 0, -1]:
		_set_t(t)
		var hits: Array[HitInstance] = []
		var di := _contact(hits)
		assert_eq(di.sweep_factor, 1.0, "t = %d: unswept until the gather stamps it" % t)
		await _land(hits)
		var factor := clampf(1.0 + _C * float(t) / float(_threshold()), 1.0 - _C, 1.0 + _C)
		assert_almost_eq(di.sweep_factor, factor, 0.0001, "t = %d: the stamp records factor(t)" % t)
		# The floater's cue reads the side of 1: FAST above, SLOW below, none at 1.
		assert_eq(signf(di.sweep_factor - 1.0), signf(float(t)), "t = %d: the cue's side" % t)
