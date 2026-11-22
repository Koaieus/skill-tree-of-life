extends GutTest

## The Shocked vertex: a vertex filled from a Shocked source is the incoming
## party (ADR 0098) at the copy's level, set off at the node it touches. On a
## node that is not Shocked the copy's arc runs alone: no centre landing, no
## node spend. On a Shocked node it is ONE arc at the summed level with one
## centre landing. Either way each primed party pays its own solo cost (its
## floor plus its own level's ring) and every reached node takes +1 Charge.
## The source never moves.
##
## Board: VolleyBoardFixture — target (450,0) hostile, linked to the cluster
## (600,0), (700,100) hostile; the attacker owns the hub and the leaves.

var _f: VolleyBoardFixture
var _light: Element = null


func before_each() -> void:
	# Held: an unheld roster reloads its defs.
	_light = ElementRoster.shared().by_id(&"lightning")


func after_each() -> void:
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _edge() -> EdgeGoOff:
	return _light.bands[0].go_off as EdgeGoOff


func _charge(node: SkillNode) -> int:
	return node.get_combat().charge()


func _read(node: SkillNode) -> TerrainRead:
	return TerrainRead.of(node.get_combat(), node)


## [param node]'s Charge set to its T + [param excess].
func _prime(node: SkillNode, excess: int) -> void:
	var c := node.get_combat()
	assert_gt(c.terrain_threshold(), 0, "fixture: %s has a T" % node.name)
	c.add_terrain(_light, c.terrain_threshold() + excess - c.charge())


## The hub (pivot) and leaf_0 as vertex 1, filled as a swing fills.
func _blade() -> BladeState:
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var s := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [_f.hub, _f.leaves[0]]
	BladeVertexFill.new().fill(s, nodes)
	return s


## Vertex 1's contact on [param on] at [param t], placed as [SwingResolve]
## places one; appended to [param hits].
func _contact(gate: BladePopResolver.LiveGate, s: BladeState, hits: Array[HitInstance],
		on: SkillNode, t := 0.5) -> BladeDamageInstance:
	var di := BladeDamageInstance.new(BladeHitEvent.new(t, 1, -1, on), gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = on
	di.attacker = _f.attacker
	di.read_node = s.vertex_node[1]
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


func _on(copies: Array[HitInstance], node: SkillNode) -> Array[HitInstance]:
	var out: Array[HitInstance] = []
	for h in copies:
		if h.target == node and h is DamageInstance:
			out.append(h)
	return out


func _marks(copies: Array[HitInstance], node: SkillNode) -> Array[BlastMark]:
	var out: Array[BlastMark] = []
	for h in copies:
		if h.blast_mark != null and h.blast_mark.centre == node and not out.has(h.blast_mark):
			out.append(h.blast_mark)
	return out


## A hostile node two hops from the target, behind cluster[0].
func _far() -> SkillNode:
	var links: Array[SkillNode] = [_f.cluster[0]]
	return _f.add_node(&"far", Vector2(900, 0), _f.hostile, links)


# --- unprimed contact ----------------------------------------------------------------

func test_a_shocked_copy_arcs_from_an_unprimed_contact_and_pays_out_of_the_copy() -> void:
	await _board()
	_prime(_f.leaves[0], 1)
	var s := _blade()
	assert_eq(_edge().level_of(s.copy_read(1)), 1, "fixture: the copy arcs at level 1")
	var source := _charge(_f.leaves[0])
	var target := _charge(_f.target)
	var reached := [_charge(_f.cluster[0]), _charge(_f.cluster[1])]
	var copy := s.vertex_charge[1]
	var hits: Array[HitInstance] = []
	_contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, _f.target)
	var copies := await _land(hits)
	assert_eq(_marks(copies, _f.target).size(), 1, "one arc from the contact node")
	assert_eq(_on(copies, _f.target).size(), 0, "no centre landing: the contact takes 1, the contact")
	for i in 2:
		assert_eq(_on(copies, _f.cluster[i]).size(), 1, "cluster %d takes 1 landing" % i)
		assert_eq(_charge(_f.cluster[i]), reached[i] + 1, "cluster %d takes the effect's +1 Charge" % i)
	assert_eq(s.vertex_charge[1], copy - _edge().void_floor - 2, "the copy pays its floor and 1 per node reached")
	assert_eq(_charge(_f.leaves[0]), source, "never the source node's ints")
	assert_eq(_charge(_f.target), target, "nor the contact node's")


func test_an_arc_reaching_the_source_node_writes_nothing_to_it() -> void:
	await _board()
	var links: Array[SkillNode] = [_f.leaves[0], _f.cluster[1]]
	var next := _f.add_node(&"next", Vector2(420, 60), _f.hostile, links)
	_prime(_f.leaves[0], 1)
	var s := _blade()
	var want := _edge().fire_level_in(null, next, _read(next), _copy(s))
	assert_true(want.effect.has(_f.leaves[0]), "fixture: the copy's arc reaches its source node")
	assert_true(want.effect.has(_f.cluster[1]), "fixture: and the contact's other neighbour")
	var source := _charge(_f.leaves[0])
	var other := _charge(_f.cluster[1])
	var copy := s.vertex_charge[1]
	var hits: Array[HitInstance] = []
	_contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, next)
	await _land(hits)
	assert_eq(_charge(_f.leaves[0]), source, "the source's Charge is unchanged, though the arc reaches it")
	assert_eq(_charge(_f.cluster[1]), other + 1, "the other neighbour takes the effect's +1 Charge")
	assert_eq(s.vertex_charge[1], maxi(0, copy - want.incoming_cost), "the copy still pays its own solo cost")


func test_a_later_contact_arcs_only_while_the_copy_stays_over_t() -> void:
	await _board()
	_prime(_f.leaves[0], 2)
	var s := _blade()
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var first: Array[HitInstance] = []
	_contact(gate, s, first, _f.target, 0.3)
	assert_eq(_marks(await _land(first), _f.target).size(), 1, "the primed copy arcs")
	assert_lte(s.vertex_charge[1], s.vertex_threshold[1], "fixture: the arc spent the copy to T")
	var copy := s.vertex_charge[1]
	var second: Array[HitInstance] = []
	_contact(gate, s, second, _f.target, 0.7)
	assert_true(_marks(await _land(second), _f.target).is_empty(), "a copy at T arcs no more")
	assert_eq(s.vertex_charge[1], copy, "and spends nothing")


# --- Shocked contact -----------------------------------------------------------------

func test_a_shocked_contact_is_one_lightning_channel_with_the_copy() -> void:
	await _board()
	var far := _far()
	_prime(_f.leaves[0], 1)
	_prime(_f.target, 1)
	var s := _blade()
	var n := _edge().level_of(s.copy_read(1))
	var m := _edge().level_of(_read(_f.target))
	assert_eq([n, m], [1, 1], "fixture: copy and node both at level 1")
	var want := _edge().fire_level_in(null, _f.target, _read(_f.target), _copy(s))
	assert_eq(want.reached.size(), 3, "fixture: level 2 reaches the cluster and the far node")
	var solo := _edge().fire(_f.target, _read(_f.target)).reached.size()
	var target := _charge(_f.target)
	var copy := s.vertex_charge[1]
	var hits: Array[HitInstance] = []
	_contact(BladePopResolver.LiveGate.new(s, _f.attacker), s, hits, _f.target)
	var copies := await _land(hits)
	assert_eq(_marks(copies, _f.target).size(), 1, "one arc at the contact node, never two")
	assert_eq(_on(copies, _f.target).size(), 1, "one centre landing: the contact node takes 2")
	assert_eq(_on(copies, far).size(), 1, "the summed level reaches two hops")
	assert_eq(_charge(_f.target), target - solo - _edge().void_floor, "the node pays its solo cost and its floor")
	assert_eq(s.vertex_charge[1], maxi(0, copy - want.incoming_cost), "the copy pays its own solo cost")
	assert_eq(want.incoming_cost, _edge().void_floor + solo, "its floor and its own L1 ring, never the combined reach")


## Vertex 1's copy as the incoming party, with a payer that records nothing
## (so a go-off's [member GoOffResult.incoming_cost] reads the copy's bill).
func _copy(s: BladeState) -> GoOffSource:
	return GoOffSource.new(s, 1, s.copy_read(1), func(_e: Element, _n: int) -> void: pass)
