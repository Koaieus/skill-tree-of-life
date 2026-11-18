extends GutTest

## A blade on Ice: every vertex contact on a Frozen node lands as a plain hit;
## the touch breaks the ice only when the vertex weighs at least the node
## (`(radius / MASS_REF_RADIUS)²`, Bunker's `blade_mass` in); the vertex pops
## only if the node is still Frozen after the contact's own terrain riders. A
## Frozen vertex (its source copy Frozen) is one-shot and hits harder by its
## copied excess. A Cold addon vertex plants Cold and changes no stat.
##
## Board: VolleyBoardFixture — target (450,0) hostile, radius from base 40;
## the attacker owns the hub and the leaves.

const _COLD_ADDON := "res://skill_node/addons/defs/cold_addon.tscn"
const _BUNKER_ADDON := "res://skill_node/addons/defs/bunker_addon.tscn"

var _f: VolleyBoardFixture
var _ice: Element
var _fire: Element
var _fa: FrozenAdmits


func after_each() -> void:
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0
	_ice = ElementRoster.shared().by_id(&"ice")
	_fire = ElementRoster.shared().by_id(&"fire")
	_fa = _ice.bands[0].admits as FrozenAdmits
	assert_not_null(_fa, "fixture: Ice's Frozen band answers with a FrozenAdmits")


func _c(n: SkillNode) -> NodeCombat:
	return CombatWorld.live().combat_for(n)


func _t(n: SkillNode) -> int:
	return _c(n).terrain_threshold()


func _cold(n: SkillNode) -> int:
	return _c(n).terrain_count(_ice)


## [param n]'s Cold set to its T + [param excess] (Frozen when excess ≥ 1).
func _freeze(n: SkillNode, excess: int) -> void:
	_c(n).add_terrain(_fire, -(_t(n) + excess) - _c(n).terrain_t())
	assert_eq(_cold(n), _t(n) + excess, "fixture: %s at Cold T + %d" % [n.name, excess])


func _tau(n: SkillNode) -> float:
	return _fa.break_fraction_max_hp * _c(n).owner().get_max_hp()


## The hub (pivot) and leaf_0 as vertex 1 of source radius [param r], filled
## as a swing fills.
func _blade(r: float) -> BladeState:
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, r]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0]]
	BladeVertexFill.new().fill(s, nodes)
	return s


## Vertex 1's contact on [param on] at [param t], dealing [param amount], its
## vertex riders plus [param riders] run on its landing as [SwingResolve] runs
## them; appended to [param hits].
func _contact(gate: BladePopResolver.LiveGate, s: BladeState, hits: Array[HitInstance],
		on: SkillNode, t := 0.5, amount := 1.0, riders: Array = []) -> BladeDamageInstance:
	var di := BladeDamageInstance.new(BladeHitEvent.new(t, 1, -1, on), gate)
	di.amount = amount
	di.type = DamageInstance.Type.PHYSICAL
	di.target = on
	di.attacker = _f.attacker
	hits.append(di)
	var landing := HitLanding.riding(di, hits)
	landing.target_mask = 0
	OnHitEffect.run_all(s.vertex_on_hit[1], landing)
	OnHitEffect.run_all(riders, landing)
	landing.place()
	return di


func _crit(h: HitInstance) -> void:
	h.is_crit = true
	h.crit_tier = 1
	h.crit_multiplier = 1.0
	h.crit_decided = true


## Lands [param hits]; returns what the beat added (copies, extras, bursts).
func _land(hits: Array[HitInstance]) -> Array[HitInstance]:
	var authored := hits.size()
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())
	return hits.slice(authored)


## The extra landings the beat put on [param node] (bursts excluded).
func _extras(added: Array[HitInstance], node: SkillNode) -> int:
	return added.filter(func(h: HitInstance) -> bool:
		return h is DamageInstance and h.target == node and not HitGather.is_burst(h)).size()


func _bursts(added: Array[HitInstance]) -> int:
	return added.filter(func(h: HitInstance) -> bool: return HitGather.is_burst(h)).size()


func _popped(hits: Array[HitInstance]) -> int:
	return hits.filter(func(h: HitInstance) -> bool: return h.popped_vertex != null).size()


func _heat_rider(power: float) -> ApplyStatusEffect:
	var r := ApplyStatusEffect.new()
	r.def = _fire.terrain
	r.power = power
	return r


## Item 8: a vertex at least as heavy as the node (equal radius) breaks the ice
## on touch, under τ and without a crit, then pops.
func _assert_heavy_touch_breaks(node: SkillNode) -> void:
	_freeze(node, 3)
	var s := _blade(node.radius)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, s, hits, node, 0.5, 1.0)
	assert_lt(1.0, _tau(node) if _c(node).owner() != null else INF, "fixture: under τ")
	var added := await _land(hits)
	assert_true(di.admitted, "the contact lands")
	assert_eq(_extras(added, node), _fa.break_channels, "the break adds its channels")
	assert_eq(_bursts(added), 1, "one burst")
	assert_eq(_cold(node), _t(node), "the ice shatters to T")
	assert_almost_eq(float(gate.result.dead_at.get(1, -1.0)), 0.5, 0.0001, "then the vertex pops at the contact")
	assert_eq(gate.result.dead_at.size(), 1, "no other vertex dies")
	assert_eq(_popped(hits), 1, "one hit carries the pop")


func test_a_vertex_as_heavy_as_an_enemy_node_shatters_it_then_pops() -> void:
	await _board()
	await _assert_heavy_touch_breaks(_f.target)


func test_a_vertex_as_heavy_as_your_own_node_shatters_it_then_pops() -> void:
	await _board()
	await _assert_heavy_touch_breaks(_f.leaves[1])


func test_a_lighter_vertex_lands_a_plain_hit_the_ice_holds_then_it_pops() -> void:
	await _board()
	_freeze(_f.target, 3)
	var s := _blade(_f.target.radius * 0.5)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, s, hits, _f.target)
	var added := await _land(hits)
	assert_true(di.admitted, "the contact lands")
	assert_eq(_extras(added, _f.target), 0, "no extra landing")
	assert_eq(_bursts(added), 0, "no burst")
	assert_eq(_cold(_f.target), _t(_f.target) + 3, "the ice holds")
	assert_almost_eq(float(gate.result.dead_at.get(1, -1.0)), 0.5, 0.0001, "the vertex pops")
	assert_eq(_popped(hits), 1, "one hit carries the pop")


func test_a_lighter_vertex_with_bunker_mass_enough_breaks_the_ice() -> void:
	await _board()
	var scene := load(_BUNKER_ADDON) as PackedScene
	assert_not_null(scene, "bunker_addon.tscn exists")
	if scene == null:
		return
	var bunker := scene.instantiate() as BunkerAddon
	bunker.blade_mass = 4.0
	_f.leaves[0].add_child(bunker)
	await get_tree().process_frame
	_freeze(_f.target, 3)
	var s := _blade(_f.target.radius * 0.5)  # (1/2)² × 4 = the node's weight
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, _f.target)
	var added := await _land(hits)
	assert_eq(_extras(added, _f.target), _fa.break_channels, "the break adds its channels")
	assert_eq(_bursts(added), 1, "one burst")
	assert_eq(_cold(_f.target), _t(_f.target), "the ice shatters")
	assert_true(gate.result.dead_at.has(1), "then the vertex pops")


func test_a_lighter_vertex_whose_contact_crits_breaks_the_ice() -> void:
	await _board()
	_freeze(_f.target, 3)
	var s := _blade(_f.target.radius * 0.5)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, s, hits, _f.target)
	_crit(di)
	var added := await _land(hits)
	assert_eq(_extras(added, _f.target), _fa.break_channels, "the crit breaks it")
	assert_eq(_bursts(added), 1, "one burst")
	assert_true(gate.result.dead_at.has(1), "then the vertex pops")


## Item 8c: the contact's own Heat thaws the node — no break, no pop.
func test_a_contact_whose_heat_thaws_the_node_does_not_pop() -> void:
	await _board()
	_freeze(_f.target, 1)
	var s := _blade(_f.target.radius * 0.5)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, s, hits, _f.target, 0.5, 1.0, [_heat_rider(2.0)])
	var added := await _land(hits)
	assert_true(di.admitted, "the contact lands")
	assert_eq(_extras(added, _f.target), 0, "no extra landing")
	assert_eq(_bursts(added), 0, "no burst")
	assert_eq(_cold(_f.target), _t(_f.target) + 1 - 2, "Cold reduced by exactly h")
	assert_false(gate.result.dead_at.has(1), "the vertex survives")
	assert_true(gate.result.pops.is_empty(), "no pop recorded")
	assert_eq(_popped(hits), 0, "no hit carries a pop")
	var later: Array[HitInstance] = []
	var next := _contact(gate, s, later, _f.target, 0.7)
	await _land(later)
	assert_true(next.admitted, "its next contact lands")


func test_a_contact_whose_heat_leaves_the_node_frozen_pops() -> void:
	await _board()
	_freeze(_f.target, 3)
	var s := _blade(_f.target.radius * 0.5)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, _f.target, 0.5, 1.0, [_heat_rider(2.0)])
	var added := await _land(hits)
	assert_eq(_bursts(added), 0, "the ice holds")
	assert_eq(_cold(_f.target), _t(_f.target) + 1, "Cold reduced by h, still Frozen")
	assert_true(gate.result.dead_at.has(1), "the vertex pops")


## Item 9: a Frozen vertex is one-shot and hits at
## `blade_damage × (1 + vertex_bonus_per_excess × excess)`.
func test_a_frozen_vertex_hits_harder_by_its_excess_then_pops() -> void:
	await _board()
	var twin := _blade(16.0)
	_freeze(_f.leaves[0], 3)
	var src_cold := _cold(_f.leaves[0])
	var s := _blade(16.0)
	assert_eq(s.vertex_one_shot[1], 1, "a Frozen copy flags the vertex one-shot")
	assert_eq(twin.vertex_one_shot[1], 0, "an unfrozen twin is not")
	assert_gt(twin.vertex_damage[1], 0.0, "fixture: the twin deals damage")
	assert_almost_eq(s.vertex_damage[1] / twin.vertex_damage[1],
			1.0 + _fa.vertex_bonus_per_excess * 3.0, 0.0001, "the overlay scales with the copied excess")
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, s, hits, _f.target, 0.5, s.vertex_damage[1])
	await _land(hits)
	assert_true(di.admitted, "its first contact lands")
	assert_true(gate.result.dead_at.has(1), "then it pops")
	assert_eq(_cold(_f.leaves[0]), src_cold, "the source node is untouched")


## Item 10: a Cold addon vertex plants Cold as a rider and changes no stat.
func test_a_cold_addon_vertex_plants_cold_and_changes_no_stat() -> void:
	await _board()
	var twin := _blade(16.0)
	var scene := load(_COLD_ADDON) as PackedScene
	assert_not_null(scene, "cold_addon.tscn exists")
	if scene == null:
		return
	_f.leaves[0].add_child(scene.instantiate())
	await get_tree().process_frame
	var s := _blade(16.0)
	assert_eq(s.vertex_damage, twin.vertex_damage, "no damage stat moves")
	assert_eq(s.vertex_blunting, twin.vertex_blunting, "no blunting stat moves")
	var before := _cold(_f.target)
	var hits: Array[HitInstance] = []
	_contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, _f.target)
	await _land(hits)
	assert_eq(_cold(_f.target), before + 1, "the contact plants one Cold")


## A contact whose own Cold freezes a node at T pops nothing: the pop needs the
## node Frozen as the beat opens and still Frozen after the riders.
func test_a_contact_whose_cold_freezes_the_node_does_not_pop() -> void:
	await _board()
	_freeze(_f.target, 0)
	var s := _blade(_f.target.radius * 0.5)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var cold := ApplyStatusEffect.new()
	cold.def = _ice.terrain
	cold.power = 1.0
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, _f.target, 0.5, 1.0, [cold])
	await _land(hits)
	assert_eq(_cold(_f.target), _t(_f.target) + 1, "fixture: the contact froze the node")
	assert_false(gate.result.dead_at.has(1), "the freezing contact pops nothing")
	var later: Array[HitInstance] = []
	var next := _contact(gate, s, later, _f.target, 0.7)
	await _land(later)
	assert_true(next.admitted, "its next contact lands")
	assert_almost_eq(float(gate.result.dead_at.get(1, -1.0)), 0.7, 0.0001,
			"and pops on the now-Frozen node")


## A Frozen vertex as heavy as a Frozen node breaks it; the one-shot pop rides
## its own landing only, never the break's extra landings.
func test_a_frozen_vertex_breaking_the_ice_carries_one_pop() -> void:
	await _board()
	_freeze(_f.leaves[0], 2)
	_freeze(_f.target, 3)
	var s := _blade(_f.target.radius)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, _f.target)
	var added := await _land(hits)
	assert_eq(_extras(added, _f.target), _fa.break_channels, "the break adds its channels")
	assert_eq(_popped(hits), 1, "one hit carries the pop")
	assert_eq(gate.result.pops.size(), 1, "one pop")


## Item 8c's last clause: a Frozen vertex's first contact pops whatever its
## riders do, a thawing Heat included.
func test_a_frozen_vertex_whose_heat_thaws_the_node_still_pops() -> void:
	await _board()
	_freeze(_f.leaves[0], 2)
	_freeze(_f.target, 1)
	var s := _blade(_f.target.radius * 0.5)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, _f.target, 0.5, 1.0, [_heat_rider(2.0)])
	await _land(hits)
	assert_lt(_cold(_f.target), _t(_f.target) + 1, "fixture: the Heat thawed the node")
	assert_true(gate.result.dead_at.has(1), "the Frozen vertex pops")
	assert_eq(_popped(hits), 1, "one hit carries the pop")


## Unallocated Frozen ground takes the touch too (terrain is side-less): a
## heavy vertex breaks it — Cold at T, no holder so no burst — then pops.
func test_a_heavy_vertex_on_unallocated_frozen_ground_breaks_it_then_pops() -> void:
	await _board()
	var ground := _f.add_node(&"ground", Vector2(450, 60))
	await get_tree().process_frame
	_freeze(ground, 3)
	var s := _blade(ground.radius)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, s, hits, ground)
	var added := await _land(hits)
	assert_true(di.admitted, "the contact lands")
	assert_eq(_cold(ground), _t(ground), "the ice shatters to T")
	assert_eq(_bursts(added), 0, "no holder, no burst")
	assert_true(gate.result.dead_at.has(1), "then the vertex pops")


## Item 8's record: the authority's shadow pass, captured and rebuilt, replays
## the same landings, the spend and exactly one pop on the live world.
func test_a_heavy_touch_replays_from_its_record() -> void:
	await _board()
	_freeze(_f.target, 3)
	var s := _blade(_f.target.radius)
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	_contact(gate, s, hits, _f.target)
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.shadow(), BeatClock.instant_clock())
	assert_eq(_cold(_f.target), _t(_f.target) + 3, "fixture: the shadow pass leaves the live world")
	var outcome := AttackOutcome.new()
	outcome.hits.assign(hits)
	var rebuilt := AttackRecord.rebuild(AttackRecord.capture(outcome, _f.graph), _f.graph)
	assert_eq(rebuilt.hits.size(), hits.size(), "the same landings cross")
	assert_eq(rebuilt.hits.filter(func(h: HitInstance) -> bool: return h.popped_vertex != null).size(), 1,
			"exactly one carries the pop")
	await OutcomeApplier.drain(HitQueue.over(rebuilt.hits), CombatWorld.live(), BeatClock.instant_clock())
	assert_eq(_cold(_f.target), _t(_f.target), "the replay spends the ice to T")
