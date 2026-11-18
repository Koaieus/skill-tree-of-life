extends GutTest

## The Heat addon: Fire's element addon, rider only. Its carrier's vertex lands
## [member ApplyStatusEffect.power] Heat on every contact the gate admits, on
## that vertex only; a refused contact lands nothing; a contact on a Frozen
## node is never refused.
##
## Board: VolleyBoardFixture — target (450,0) hostile; cluster (600,0),
## (700,100) hostile; the attacker owns the hub and the leaves.

const _HEAT_ADDON := "res://skill_node/addons/defs/heat_addon.tscn"
const _SPIKE_SCENE := preload("res://skill_node/addons/defs/spike_ring_addon.tscn")

var _f: VolleyBoardFixture


func after_each() -> void:
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)


func _heat(node: SkillNode) -> int:
	return node.get_combat().terrain_t()


## The Heat addon, loaded at run time (a missing scene fails an assert, never
## the parse).
func _addon() -> SkillNodeAddon:
	var scene := load(_HEAT_ADDON) as PackedScene
	assert_not_null(scene, "heat_addon.tscn exists")
	return scene.instantiate() as SkillNodeAddon if scene != null else null


## The hub (pivot), leaf_0 carrying the Heat addon as vertex 1 and the plain
## leaf_1 as vertex 2, filled as a swing fills.
func _blade() -> BladeState:
	var addon := _addon()
	if addon != null:
		_f.leaves[0].add_child(addon)
	await get_tree().process_frame
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0), Vector2(430, 10)]
	var radii: Array[float] = [16.0, 16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0], _f.leaves[1]]
	BladeVertexFill.new().fill(s, nodes)
	return s


## Vertex [param particle]'s contact on [param on] at [param t], its riders
## run on its landing as [SwingResolve] runs them; appended to [param hits].
func _contact(gate: BladePopResolver.LiveGate, s: BladeState, hits: Array[HitInstance],
		particle: int, on: SkillNode, t := 0.5) -> BladeDamageInstance:
	var di := BladeDamageInstance.new(BladeHitEvent.new(t, particle, -1, on), gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = on
	di.attacker = _f.attacker
	hits.append(di)
	var landing := HitLanding.riding(di, hits)
	landing.target_mask = SkillNode.Ownership.HOSTILE
	OnHitEffect.run_all(s.vertex_on_hit[particle], landing)
	landing.place()
	return di


func _land(hits: Array[HitInstance]) -> void:
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())


func _power() -> int:
	var addon := _addon()
	if addon == null:
		return -1
	var power := -1
	for effect in addon.on_hit_effects:
		if effect is ApplyStatusEffect and (effect as ApplyStatusEffect).def.id == &"heat":
			power = roundi((effect as ApplyStatusEffect).power)
	addon.queue_free()
	return power


func test_the_addon_rides_heat_at_its_power() -> void:
	assert_eq(_power(), 1, "the innate Heat per vertex: ApplyStatusEffect.power 1")


func test_its_vertex_lands_its_power_on_every_contact_on_that_vertex_only() -> void:
	await _board()
	var s: BladeState = await _blade()
	var a := _f.target
	var b: SkillNode = _f.cluster[0]
	var a_t := _heat(a)
	var b_t := _heat(b)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, 1, a, 0.3)
	_contact(gate, s, hits, 2, b, 0.4)
	await _land(hits)
	assert_eq(_heat(a), a_t + _power(), "the carrier's vertex lands its Heat")
	assert_eq(_heat(b), b_t, "the plain vertex lands none")
	var more: Array[HitInstance] = []
	_contact(gate, s, more, 1, b, 0.6)
	await _land(more)
	assert_eq(_heat(b), b_t + _power(), "and again on its next contact")


func test_a_refused_contact_lands_nothing() -> void:
	await _board()
	var spiked: SkillNode = _f.cluster[1]
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = 5.0
	spike.local_modifiers = [mod]
	spiked.add_child(spike)
	var s: BladeState = await _blade()
	var a_t := _heat(_f.target)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, 1, spiked, 0.3)
	var later := _contact(gate, s, hits, 1, _f.target, 0.6)
	await _land(hits)
	assert_eq(gate.result.pops.size(), 1, "fixture: the spiked defender popped the vertex")
	assert_false(later.admitted, "fixture: the popped vertex's later contact is refused")
	assert_eq(_heat(_f.target), a_t, "a refused contact lands no Heat")


func test_a_contact_on_a_frozen_node_is_never_refused() -> void:
	await _board()
	var c := _f.target.get_combat()
	c.add_terrain(ElementRoster.shared().by_id(&"ice"), c.terrain_threshold() + 1 + c.terrain_t())
	assert_lt(c.terrain_t(), -c.terrain_threshold(), "fixture: the target is Frozen")
	var s: BladeState = await _blade()
	var t := _heat(_f.target)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, s, hits, 1, _f.target)
	await _land(hits)
	assert_true(di.admitted, "the contact on ice lands")
	assert_gt(_heat(_f.target), t, "and its Heat rider lands with it")
