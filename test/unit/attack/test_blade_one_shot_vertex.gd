extends GutTest

## The one-shot seat (#1804): a flagged vertex's first contact lands its damage
## and then pops the vertex, the landed hit carrying the pop; every later
## contact is refused. An unflagged vertex is unchanged.
##
## Board: VolleyBoardFixture — target (450,0) hostile, unspiked.

var _f: VolleyBoardFixture


func after_each() -> void:
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _blade(one_shot: bool) -> BladeState:
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0]]
	BladeVertexFill.new().fill(s, nodes)
	if one_shot:
		s.vertex_one_shot[1] = 1
	return s


func _contact(gate: BladePopResolver.LiveGate, hits: Array[HitInstance], t: float) -> BladeDamageInstance:
	var di := BladeDamageInstance.new(BladeHitEvent.new(t, 1, -1, _f.target), gate)
	di.amount = 10.0
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


func test_a_one_shot_vertex_lands_its_first_contact_then_pops() -> void:
	await _board()
	var gate := BladePopResolver.LiveGate.new(_blade(true), _f.attacker)
	var hp := _f.target.get_combat().get_current_hp()
	var hits: Array[HitInstance] = []
	var first := _contact(gate, hits, 0.5)
	var second := _contact(gate, hits, 0.7)
	await _land(hits)
	assert_true(first.admitted, "the first contact lands")
	assert_lt(_f.target.get_combat().get_current_hp(), hp, "and deals its damage")
	assert_eq(first.popped_vertex, _f.target, "the landed hit carries its pop")
	assert_eq(gate.result.pops.size(), 1, "one pop")
	assert_almost_eq(gate.result.pops[0].t, 0.5, 0.0001, "at the first contact's t")
	assert_false(second.admitted, "the next contact is refused")
	assert_almost_eq(float(gate.result.dead_at.get(1, -1.0)), 0.5, 0.0001,
			"the vertex is dead from the first contact's t")


func test_an_unflagged_vertex_is_unchanged() -> void:
	await _board()
	var gate := BladePopResolver.LiveGate.new(_blade(false), _f.attacker)
	var hits: Array[HitInstance] = []
	var first := _contact(gate, hits, 0.5)
	var second := _contact(gate, hits, 0.7)
	await _land(hits)
	assert_true(first.admitted and second.admitted, "both contacts land")
	assert_null(first.popped_vertex, "nothing pops")
	assert_true(gate.result.pops.is_empty(), "no pop recorded")
