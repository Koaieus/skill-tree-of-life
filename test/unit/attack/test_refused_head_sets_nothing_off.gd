extends GutTest

## A head its gate refuses takes no part in stage one: no go-off, no spend, no
## copies — the node's Heat and the vertex's copied terrain stay as they were.
## The three blade refusals ([method BladePopResolver.LiveGate.admit]): this
## contact pops on spikes, the vertex was already popped, the target was
## deallocated first. The dud arrow is in test_catalyst_status.gd.
##
## Board: VolleyBoardFixture — target (450,0) hostile, radius 40; cluster
## (600,0), (700,100) hostile; the attacker owns the hub and the leaves.

const _SPIKE_SCENE := preload("res://skill_node/addons/defs/spike_ring_addon.tscn")

var _f: VolleyBoardFixture


func after_each() -> void:
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


func _heat(node: SkillNode) -> int:
	return node.get_combat().terrain_t()


func _burning(node: SkillNode) -> bool:
	var c := node.get_combat()
	return c.terrain_t() > c.terrain_threshold()


## [param node]'s Heat set to its T + [param excess]: Burning, primed.
func _prime(node: SkillNode, excess: int) -> void:
	var c := node.get_combat()
	assert_gt(c.terrain_threshold(), 0, "fixture: %s has a T" % node.name)
	c.add_terrain(_fire(), c.terrain_threshold() + excess - c.terrain_t())


## A spike ring on [param node] that pops vertex 1 on contact.
func _spike(node: SkillNode) -> void:
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = 5.0
	spike.local_modifiers = [mod]
	node.add_child(spike)


## The hub (pivot) and leaf_0 as vertex 1, filled as a swing fills: leaf_0
## primed first, so vertex 1 is a Burning vertex.
func _blade() -> BladeState:
	_prime(_f.leaves[0], 8)
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0]]
	BladeVertexFill.new().fill(s, nodes)
	assert_gt(s.vertex_t[1], 0, "fixture: vertex 1 carries copied Heat")
	return s


## Vertex 1's contact on [param on] at [param t], placed as a swing places it.
func _contact(gate: BladePopResolver.LiveGate, s: BladeState, hits: Array[HitInstance],
		on: SkillNode, t := 0.5) -> BladeDamageInstance:
	var di := BladeDamageInstance.new(BladeHitEvent.new(t, 1, -1, on), gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = on
	di.attacker = _f.attacker
	hits.append(di)
	var landing := HitLanding.riding(di, hits)
	landing.target_mask = SkillNode.Ownership.HOSTILE
	OnHitEffect.run_all(s.vertex_on_hit[1], landing)
	landing.place()
	return di


func _land(hits: Array[HitInstance]) -> Array[HitInstance]:
	var authored := hits.size()
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())
	return hits.slice(authored)


func test_a_contact_that_pops_on_spikes_sets_nothing_off() -> void:
	await _board()
	_prime(_f.target, 3)
	_spike(_f.target)
	var s := _blade()
	var heat := _heat(_f.target)
	var copy_t := s.vertex_t[1]
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var popped := _contact(gate, s, hits, _f.target)
	var copies := await _land(hits)
	assert_false(popped.admitted, "fixture: the spike pop refuses its own contact")
	assert_eq(gate.result.pops.size(), 1, "fixture: the vertex popped")
	assert_eq(_heat(_f.target), heat, "the Burning node keeps its Heat")
	assert_eq(s.vertex_t[1], copy_t, "the vertex's copy is unspent")
	assert_eq(copies.size(), 0, "no copies")


func test_a_contact_of_an_already_popped_vertex_sets_nothing_off() -> void:
	await _board()
	_prime(_f.target, 3)
	_spike(_f.cluster[1])
	var s := _blade()
	var heat := _heat(_f.target)
	var copy_t := s.vertex_t[1]
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, _f.cluster[1], 0.3)
	var later := _contact(gate, s, hits, _f.target, 0.6)
	var copies := await _land(hits)
	assert_eq(gate.result.pops.size(), 1, "fixture: the spiked defender popped the vertex")
	assert_false(later.admitted, "fixture: the popped vertex's later contact is refused")
	assert_eq(_heat(_f.target), heat, "the Burning node keeps its Heat")
	assert_eq(s.vertex_t[1], copy_t, "neither refused contact spends the vertex's copy")
	assert_eq(copies.size(), 0, "no copies")


func test_a_contact_on_a_deallocated_target_sets_nothing_off() -> void:
	await _board()
	_prime(_f.target, 3)
	var s := _blade()
	_f.target.owned_by = null
	assert_true(_burning(_f.target), "fixture: the deallocated node is still primed")
	var heat := _heat(_f.target)
	var copy_t := s.vertex_t[1]
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var refused := _contact(gate, s, hits, _f.target)
	var copies := await _land(hits)
	assert_false(refused.admitted, "fixture: a deallocated target is refused")
	assert_eq(_heat(_f.target), heat, "the Burning node keeps its Heat")
	assert_eq(s.vertex_t[1], copy_t, "the vertex's copy is unspent")
	assert_eq(copies.size(), 0, "no copies")


func test_an_admitted_contact_on_the_same_board_still_goes_off() -> void:
	await _board()
	_prime(_f.target, 3)
	var s := _blade()
	var heat := _heat(_f.target)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var landed := _contact(gate, s, hits, _f.target)
	var copies := await _land(hits)
	assert_true(landed.admitted, "fixture: the contact lands")
	assert_lt(_heat(_f.target), heat, "a landed contact sets the node off and pays")
	assert_gt(copies.size(), 0, "and blasts copies")
