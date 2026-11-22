extends GutTest

## A blade vertex copies its source node's terrain at fill (#1804): the copy is
## a read, spending it never touches the source, and a contact's head hands the
## gather that copy as a go-off source it sets off at the struck node and pays
## for out of the copy alone.
##
## Board: VolleyBoardFixture — target (450,0) hostile; cluster[0] (600,0)
## hostile; the attacker owns the hub and the leaves.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


## A go-off that reaches one fixed node and counts its fires (base law: spend 1
## per other node reached).
class _SpyGoOff:
	extends GoOff
	func _init() -> void:
		void_floor = 0  # not about the pay rule

	var to: SkillNode = null
	var fired := 0

	func fire(node: SkillNode, read: TerrainRead) -> GoOffResult:
		fired += 1
		return super.fire(node, read)

	func _reach(_node: SkillNode, _read: TerrainRead) -> Array[GoOffResult.Reach]:
		var out: Array[GoOffResult.Reach] = [GoOffResult.Reach.new(to, 1)]
		return out


var _f: VolleyBoardFixture
var _held_go_off: GoOff = null


func after_each() -> void:
	if _held_go_off != null:
		_fire().bands[0].go_off = _held_go_off
		_held_go_off = null
	CombatWorld.reset_live()


func _board() -> void:
	CombatWorld.reset_live()
	_f = await VolleyBoardFixture.build(self, true)
	_f.target.base_radius = 40.0


func _fire() -> Element:
	return ElementRoster.shared().by_id(&"fire")


## Fire's first band goes off through a spy reaching [param to] (put back after).
func _install(to: SkillNode) -> _SpyGoOff:
	var spy := _SpyGoOff.new()
	spy.to = to
	_held_go_off = _fire().bands[0].go_off
	_fire().bands[0].go_off = spy
	return spy


func _heat(node: SkillNode) -> int:
	return node.get_combat().terrain_t()


## [param node]'s Heat set to its T + [param excess].
func _prime(node: SkillNode, excess: int) -> void:
	var c := node.get_combat()
	assert_gt(c.terrain_threshold(), 0, "fixture: %s has a T" % node.name)
	c.add_terrain(_fire(), c.terrain_threshold() + excess - c.terrain_t())


## The hub (pivot) plus the leaves as vertices 1.., filled as a swing fills.
func _blade(vertices: int = 1) -> BladeState:
	var positions: Array[Vector2] = [Vector2(-400, 0)]
	var radii: Array[float] = [16.0]
	var edges: Array[Vector2i] = []
	var nodes: Array[SkillNode] = [_f.hub]
	for i in vertices:
		positions.append(Vector2(430, 10.0 * i))
		radii.append(16.0)
		edges.append(Vector2i(0, i + 1))
		nodes.append(_f.leaves[i])
	var s := BladeState.build(positions, 0, edges, radii)
	BladeVertexFill.new().fill(s, nodes)
	return s


## Vertex [param particle]'s contact on the target at [param t], placed as
## [SwingResolve] places one: the head of its own landing, appended to [param hits].
func _contact(gate: BladePopResolver.LiveGate, hits: Array[HitInstance], particle := 1,
		t := 0.5) -> BladeDamageInstance:
	var di := BladeDamageInstance.new(BladeHitEvent.new(t, particle, -1, _f.target), gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = _f.target
	di.attacker = _f.attacker
	hits.append(di)
	var landing := HitLanding.riding(di, hits)
	landing.target_mask = SkillNode.Ownership.HOSTILE
	landing.place()
	return di


func _land(hits: Array[HitInstance]) -> Array[HitInstance]:
	var authored := hits.size()
	await OutcomeApplier.drain(HitQueue.over(hits), CombatWorld.live(), BeatClock.instant_clock())
	return hits.slice(authored)


func _arg_count(script: Script, method: StringName) -> int:
	for m in script.get_script_method_list():
		if m.name == method:
			return (m.args as Array).size()
	return -1


# --- acceptance 1: the copy ----------------------------------------------------

func test_a_primed_source_copies_its_terrain_onto_the_vertex() -> void:
	await _board()
	_prime(_f.leaves[0], 2)
	var c := _f.leaves[0].get_combat()
	var s := _blade()
	assert_eq(s.vertex_t[1], c.terrain_t(), "the vertex copies the source's t")
	assert_eq(s.vertex_charge[1], c.charge(), "and its Charge")
	assert_eq(s.vertex_threshold[1], c.terrain_threshold(), "and its T")
	assert_eq(s.vertex_cap[1], c.terrain_cap(), "and its cap")
	assert_not_null(s.copy_read(1).band(_fire()), "past T: the copy sits in a band")


func test_spending_the_copy_leaves_the_source_unchanged() -> void:
	await _board()
	_prime(_f.leaves[0], 2)
	var held := _heat(_f.leaves[0])
	var s := _blade()
	s.spend_copy(1, _fire(), 2)
	assert_eq(s.vertex_t[1], held - 2, "the copy is spent")
	assert_eq(_heat(_f.leaves[0]), held, "the source NodeState keeps its stacks")


func test_a_source_under_t_copies_to_an_inert_vertex() -> void:
	await _board()
	var c := _f.leaves[0].get_combat()
	c.add_terrain(_fire(), 1 - c.terrain_t())
	assert_lt(c.terrain_t(), c.terrain_threshold(), "fixture: under T")
	var s := _blade()
	assert_eq(s.vertex_t[1], 1, "the under-T heat is copied")
	for e: Element in ElementRoster.shared().elements:
		assert_null(s.copy_read(1).band(e), "an inert copy answers no band (%s)" % e.id)


# --- acceptance 2: one filler ------------------------------------------------------

func test_preview_and_plan_fill_agree_on_the_copy() -> void:
	var graph: Graph = TestWorld.create(self).graph
	var alloc := TestWorld.allocator_for(graph)
	var entity := Entity.new()
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(entity)
	var nodes: Array[SkillNode] = []
	for nm in ["Source", "Joint", "Tip"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = nm
		graph.add_skill_node(sn)
		nodes.append(sn)
	graph.add_edge(nodes[0], nodes[1])
	graph.add_edge(nodes[1], nodes[2])
	await get_tree().process_frame
	for sn in nodes:
		alloc.force_allocate(entity, sn)
	var tip := nodes[2].get_combat()
	tip.add_terrain(_fire(), tip.terrain_threshold() + 1)
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = entity
	plan.source = nodes[0]
	var members: Array[SkillNode] = [nodes[1], nodes[2]]
	plan.blade_nodes = members
	var resolve_state := plan.build_blade_state()
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	blade.build_from_skill_nodes(nodes, plan.source, plan.get_induced_edges(), entity, plan.vertex_fill)
	var visual_state := blade.state
	assert_gt(resolve_state.vertex_t[2], 0, "fixture: the tip's heat is copied")
	assert_eq(visual_state.vertex_t, resolve_state.vertex_t, "one fill: t")
	assert_eq(visual_state.vertex_charge, resolve_state.vertex_charge, "one fill: Charge")
	assert_eq(visual_state.vertex_threshold, resolve_state.vertex_threshold, "one fill: T")
	assert_eq(visual_state.vertex_cap, resolve_state.vertex_cap, "one fill: cap")


# --- acceptance 3: the go-off source -------------------------------------------

func test_a_plain_head_answers_no_source_and_the_signatures_stand() -> void:
	assert_null(DamageInstance.new().go_off_source(), "a plain DamageInstance answers null")
	assert_eq(_arg_count(HitGather, &"stage_one"), 4, "stage_one: the group, the world, the queue, the crit stream")
	assert_eq(_arg_count(OutcomeApplier, &"apply"), 4, "apply keeps its parameter list")
	assert_eq(_arg_count(OutcomeApplier, &"drain"), 6, "drain keeps its parameter list")


func test_a_primed_copy_goes_off_from_the_contact_and_spends_only_the_copy() -> void:
	await _board()
	_prime(_f.leaves[0], 2)
	var s := _blade()
	var source_t := _heat(_f.leaves[0])
	var target_t := _heat(_f.target)
	var spy := _install(_f.cluster[0])
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, hits)
	var src := di.go_off_source()
	assert_not_null(src, "a vertex contact answers a go-off source")
	assert_same(src.holder, s, "naming its blade")
	assert_eq(src.index, 1, "and its vertex")
	var copy_t := s.vertex_t[1]
	var copies := await _land(hits)
	assert_eq(spy.fired, 1, "the copy's band went off once")
	assert_eq(s.vertex_t[1], copy_t - 1, "the go-off spent the vertex copy")
	assert_eq(_heat(_f.leaves[0]), source_t, "never the source node's ints")
	assert_eq(_heat(_f.target), target_t, "never the struck node's ints")
	assert_true(copies.any(func(h: HitInstance) -> bool: return h.target == _f.cluster[0]),
			"the go-off's copy reached its node")


func test_an_inert_copy_answers_a_source_that_sets_nothing_off() -> void:
	await _board()
	var s := _blade()
	var spy := _install(_f.cluster[0])
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var di := _contact(gate, hits)
	assert_not_null(di.go_off_source(), "an inert vertex still answers a source")
	var copy_t := s.vertex_t[1]
	var copies := await _land(hits)
	assert_eq(spy.fired, 0, "nothing goes off from an inert copy")
	assert_eq(s.vertex_t[1], copy_t, "and its copy is unchanged")
	assert_true(copies.is_empty(), "no copy lands anywhere")


func test_two_primed_vertices_on_one_node_each_spend_only_their_own_copy() -> void:
	await _board()
	_prime(_f.leaves[0], 2)
	_prime(_f.leaves[1], 3)
	var s := _blade(2)
	var spy := _install(_f.cluster[0])
	var gate := BladePopResolver.LiveGate.new(s, _f.attacker)
	var hits: Array[HitInstance] = []
	var a := _contact(gate, hits, 1, 0.5)
	var b := _contact(gate, hits, 2, 0.5)
	assert_true(a.is_head and b.is_head, "two contacts, two heads")
	var t1 := s.vertex_t[1]
	var t2 := s.vertex_t[2]
	await _land(hits)
	assert_eq(spy.fired, 2, "each head's copy went off")
	assert_eq(s.vertex_t[1], t1 - 1, "vertex 1 paid once, for its own")
	assert_eq(s.vertex_t[2], t2 - 1, "vertex 2 paid once, for its own")
