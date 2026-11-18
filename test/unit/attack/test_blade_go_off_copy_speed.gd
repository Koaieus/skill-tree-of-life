extends GutTest

## A blade contact's go-off copies carry the contact's raw amount — the
## coefficient times the speed curve — never the bare coefficient: the curve is
## stamped on the head as its gather opens, before the copies are sized off it.
##
## Board: VolleyBoardFixture — target (450,0) hostile; the attacker owns the
## hub and the leaves. The sweep factor is held at 1 (c = 0) and Burning's own
## damage silenced, so a copy's amount is the head's raw amount × share.

const _M := 3.0
const _V_HALF := 400.0
const _K := 10.0
const _V := 600.0

var _f: VolleyBoardFixture
var _disc: DiscGoOff = null
var _held_per_power := 0.0


func after_each() -> void:
	if _disc != null:
		_disc.damage_per_power = _held_per_power
		_disc = null
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0
	var board := _f.attacker.stat_board
	board.blade_speed_multiplier_max.base_value = _M
	board.blade_speed_half.base_value = _V_HALF
	board.blade_temperature_speed.base_value = 0.0
	board.crit_chance.base_value = 0.0


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


## The target primed (Burning), its disc's own damage silenced (put back after).
func _prime_silenced() -> DiscGoOff:
	var fire := _fire()
	_disc = fire.bands[0].go_off as DiscGoOff
	assert_not_null(_disc, "fixture: Burning goes off as a disc")
	_held_per_power = _disc.damage_per_power
	_disc.damage_per_power = 0.0
	var c := _f.target.get_combat()
	c.add_terrain(fire, c.terrain_threshold() + 1 - c.terrain_t())
	return _disc


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


func test_a_go_off_copy_carries_the_speed_scaled_amount() -> void:
	await _board()
	var disc := _prime_silenced()
	var curve := BladeState.speed_damage_multiplier(_V, _M, _V_HALF)
	assert_gt(absf(curve - 1.0), 0.1, "fixture: the curve at this speed is not unit")
	var hits: Array[HitInstance] = []
	_contact(hits)
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())
	var copies := hits.slice(1).filter(
			func(h): return h is DamageInstance and h.target == _f.target)
	assert_eq(copies.size(), 1, "the disc's centre landing on the struck node")
	if copies.is_empty():
		return
	assert_almost_eq(hits[0].amount, _K * curve, 0.0001, "the head lands k × curve(v)")
	assert_almost_eq((copies[0] as DamageInstance).amount, _K * curve * disc.share, 0.0001,
			"its copy carries the same speed-scaled amount, not the bare coefficient")
