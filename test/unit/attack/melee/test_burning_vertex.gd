extends GutTest

## The Burning vertex: a vertex filled from a Burning source carries a Fire
## shape of power copy − T, set off at the node it touches. The disc is centred
## on, and sized by, the contact node. On a node that is not Burning (Frozen
## included) the shape runs alone: no centre landing, no node spend, the copy
## pays 1 per reached node. On a Burning node it adds up with the node's own
## go-off as ONE Fire channel: one blast, one centre landing, the node pays its
## solo cost (floored), the copy 1 per reached node. The source never moves.
##
## Board: VolleyBoardFixture — target (450,0) hostile, radius 40; cluster
## (600,0), (700,100) hostile; the attacker owns the hub and the leaves.

const _HEAT_ADDON := "res://skill_node/addons/defs/heat_addon.tscn"

var _f: VolleyBoardFixture


func after_each() -> void:
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


func _disc() -> DiscGoOff:
	return _fire().bands[0].go_off as DiscGoOff


func _heat(node: SkillNode) -> int:
	return node.get_combat().terrain_t()


func _read(node: SkillNode) -> TerrainRead:
	return TerrainRead.of(node.get_combat(), node)


## [param node]'s Heat set to its T + [param excess].
func _prime(node: SkillNode, excess: int) -> void:
	var c := node.get_combat()
	assert_gt(c.terrain_threshold(), 0, "fixture: %s has a T" % node.name)
	c.add_terrain(_fire(), c.terrain_threshold() + excess - c.terrain_t())


## [param node] Frozen: its Cold one past its T.
func _freeze(node: SkillNode) -> void:
	var c := node.get_combat()
	c.add_terrain(ElementRoster.shared().by_id(&"ice"), c.terrain_threshold() + 1 + c.terrain_t())
	assert_lt(c.terrain_t(), -c.terrain_threshold(), "fixture: %s is Frozen" % node.name)


## The hub (pivot) and leaf_0 as vertex 1, filled as a swing fills.
func _blade() -> BladeState:
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0]]
	BladeVertexFill.new().fill(s, nodes)
	return s


## Vertex 1's contact on [param on] at [param t], its riders run on its
## landing as [SwingResolve] runs them; appended to [param hits].
func _contact(gate: BladePopResolver.LiveGate, s: BladeState, hits: Array[HitInstance],
		on: SkillNode, t := 0.5, amount := 10.0) -> BladeDamageInstance:
	var di := BladeDamageInstance.new(BladeHitEvent.new(t, 1, -1, on), gate)
	di.amount = amount
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


## The damage copies among [param copies] that land on [param node].
func _on(copies: Array[HitInstance], node: SkillNode) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for h in copies:
		if h.target == node and h is DamageInstance:
			out.append(h)
	return out


## The distinct marks [param copies] carry, centred on [param node].
func _marks(copies: Array[HitInstance], node: SkillNode) -> Array[BlastMark]:
	var out: Array[BlastMark] = []
	for h in copies:
		if h.blast_mark != null and h.blast_mark.centre == node and not out.has(h.blast_mark):
			out.append(h.blast_mark)
	return out


## The hostile nodes of [param result]'s reach (the copies the hit's mask lets on).
func _hostile(result: GoOffResult) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	for r in result.reached:
		if r.node.owned_by == _f.hostile:
			out.append(r.node)
	return out


## [param read]'s Heat zeroed: what an unprimed node of the same T reads.
func _unprimed(read: TerrainRead) -> TerrainRead:
	var out := TerrainRead.new()
	out.node = read.node
	out.threshold = read.threshold
	out.cap = read.cap
	return out


# --- 2: unprimed contact ------------------------------------------------------------

func test_an_unprimed_contact_booms_the_vertexs_disc_sized_by_the_contact() -> void:
	await _board()
	_prime(_f.leaves[0], 8)
	var s := _blade()
	var shape := _disc().power_at(null, s.copy_read(1))
	assert_eq(shape, 8, "fixture: the vertex's power is copy − T")
	var want := _disc().fire_shaped_in(null, _f.target, _read(_f.target), float(shape))
	assert_gt(want.reached.size(), 0, "fixture: the disc reaches someone")
	var source_t := _heat(_f.leaves[0])
	var target_t := _heat(_f.target)
	var copy_t := s.vertex_t[1]
	assert_gt(copy_t, want.reached.size(), "fixture: the copy affords its reach")
	var hits: Array[HitInstance] = []
	_contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, _f.target)
	var copies := await _land(hits)
	var marks := _marks(copies, _f.target)
	assert_eq(marks.size(), 1, "one blast at the contact node")
	if marks.is_empty():
		return
	var r := _f.target.radius
	assert_almost_eq(marks[0].reach, _disc().shape_disc_radius(shape, 0.0, r), 0.001,
			"radius shape_disc_radius(copy − T, 0, R_contact)")
	assert_almost_eq(marks[0].reach, _disc().disc_radius(shape, r), 0.001, "= disc_radius(copy − T, R)")
	assert_eq(_heat(_f.leaves[0]), source_t, "the source's Heat is unchanged")
	assert_eq(_heat(_f.target), target_t, "an unprimed contact node pays nothing")
	assert_eq(s.vertex_t[1], copy_t - want.reached.size(), "the copy pays 1 per node reached")


func test_a_disc_reaching_no_other_node_spends_nothing_and_lands_nothing() -> void:
	await _board()
	var lone := _f.add_node(&"lone", Vector2(9000, 0), _f.hostile)
	_prime(_f.leaves[0], 1)
	var s := _blade()
	assert_true(_disc().fire_shaped_in(null, lone, _read(lone), 1.0).reached.is_empty(),
			"fixture: nothing near the lone node")
	var copy_t := s.vertex_t[1]
	var hits: Array[HitInstance] = []
	_contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, lone)
	var copies := await _land(hits)
	assert_eq(s.vertex_t[1], copy_t, "a disc reaching no one spends nothing")
	assert_true(copies.is_empty(), "and adds no landing")


func test_a_later_contact_goes_off_only_while_the_copy_stays_over_t() -> void:
	await _board()
	_prime(_f.leaves[0], 1)
	var s := _blade()
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var first: Array[HitInstance] = []
	_contact(gate, s, first, _f.target, 0.3)
	var first_copies := await _land(first)
	assert_eq(_marks(first_copies, _f.target).size(), 1, "the primed copy goes off")
	assert_lte(s.vertex_t[1], s.vertex_threshold[1], "fixture: the first boom spent the copy to T")
	var copy_t := s.vertex_t[1]
	var second: Array[HitInstance] = []
	_contact(gate, s, second, _f.target, 0.7)
	var second_copies := await _land(second)
	assert_true(_marks(second_copies, _f.target).is_empty(), "a copy at T goes off no more")
	assert_eq(s.vertex_t[1], copy_t, "and spends nothing")


# --- 2b: landings -----------------------------------------------------------------------

func test_an_unprimed_contact_lands_once_and_each_reached_node_once_a_generation_later() -> void:
	await _board()
	_prime(_f.leaves[0], 2)
	_f.leaves[0].add_child(load(_HEAT_ADDON).instantiate())
	await get_tree().process_frame
	var s := _blade()
	var shape := float(_disc().power_at(null, s.copy_read(1)))
	var want := _hostile(_disc().fire_shaped_in(null, _f.target, _read(_f.target), shape))
	assert_gt(want.size(), 0, "fixture: the disc reaches a hostile node")
	var target_t := _heat(_f.target)
	assert_lt(target_t + 1, _f.target.get_combat().terrain_threshold(), "fixture: the rider leaves it unprimed")
	var hits: Array[HitInstance] = []
	_contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, _f.target)
	var copies := await _land(hits)
	assert_eq(_on(copies, _f.target).size(), 0, "no centre landing: the contact node takes 1, the contact")
	for n in want:
		var on := _on(copies, n)
		assert_eq(on.size(), 1, "%s takes 1 landing" % n.name)
		if not on.is_empty():
			assert_not_null(on[0].blast_mark, "%s's entry carries the blast mark" % n.name)
			if on[0].blast_mark != null:
				assert_eq(on[0].blast_mark.generation, 0,
						"%s's mark fired at the contact's read: its entry lands a generation later" % n.name)
	assert_eq(_heat(_f.target), target_t + 1, "the Heat rider lands once on the contact node")


# --- 2c: Burning contact node -------------------------------------------------------

func test_a_burning_contact_adds_up_as_one_fire_channel() -> void:
	await _board()
	_prime(_f.leaves[0], 8)
	_prime(_f.target, 1)
	var s := _blade()
	var shape := float(_disc().power_at(null, s.copy_read(1)))
	var e := float(_disc().power_at(null, _read(_f.target)))
	assert_eq(e, 1.0, "fixture: the contact node's excess")
	var want := _disc().fire_shaped_in(null, _f.target, _read(_f.target), shape)
	var solo := want.spend_at_read()
	assert_gte(solo, _disc().void_floor, "fixture: the solo spend, its floor included")
	var target_t := _heat(_f.target)
	var copy_t := s.vertex_t[1]
	assert_gt(copy_t, want.reached.size(), "fixture: the copy affords the combined reach")
	var hits: Array[HitInstance] = []
	_contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, _f.target)
	var copies := await _land(hits)
	var marks := _marks(copies, _f.target)
	assert_eq(marks.size(), 1, "one blast at the contact node, not two")
	if not marks.is_empty():
		assert_almost_eq(marks[0].reach, _disc().shape_disc_radius(shape, e, _f.target.radius), 0.001,
				"radius shape_disc_radius(copy − T, e, R_contact)")
	assert_eq(_on(copies, _f.target).size(), 1, "one centre landing: the contact node takes 2")
	assert_eq(_heat(_f.target), target_t - solo, "the node pays exactly its solo spend")
	assert_eq(s.vertex_t[1], copy_t - want.reached.size(),
			"the copy pays 1 per node the combined disc reaches")


# --- 2d: Frozen contact node ----------------------------------------------------------

func test_a_frozen_contact_runs_the_disc_alone() -> void:
	await _board()
	_prime(_f.leaves[0], 2)
	_freeze(_f.target)
	var s := _blade()
	var shape := float(_disc().power_at(null, s.copy_read(1)))
	var want := _hostile(_disc().fire_shaped_in(null, _f.target, _unprimed(_read(_f.target)), shape))
	assert_gt(want.size(), 0, "fixture: the alone disc reaches a hostile node")
	var target_t := _heat(_f.target)
	var hits: Array[HitInstance] = []
	# A light contact (under the Frozen band's flat breaker), so the ice holds.
	var di := _contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, _f.target, 0.5, 1.0)
	var copies := await _land(hits)
	assert_true(di.admitted, "a contact on a Frozen node is never refused")
	var marks := _marks(copies, _f.target)
	assert_eq(marks.size(), 1, "the vertex's disc goes off")
	if not marks.is_empty():
		assert_almost_eq(marks[0].reach, _disc().shape_disc_radius(shape, 0.0, _f.target.radius), 0.001,
				"the alone radius")
	var got: Array[SkillNode] = []
	for h in copies:
		if h is DamageInstance and h.target != _f.target and not got.has(h.target):
			got.append(h.target)
	got.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return a.name < b.name)
	want.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return a.name < b.name)
	assert_eq(got, want, "it reaches what it reaches from an unprimed node")
	assert_eq(_on(copies, _f.target).size(), 0, "no centre landing")
	assert_eq(_heat(_f.target), target_t, "the Frozen node pays nothing")
