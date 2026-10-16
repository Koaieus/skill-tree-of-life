extends GutTest

## `explosive_barrel_addon.tscn` — Explosive × Addon. Barrels stack; at the
## owner's turn start an allocated carrier tops its explosive charges up to
## its barrel count, and removing a barrel spends one charge if any. Counts
## are read off the carrier's barrels and the live status, never literals.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BARREL_SCENE := preload("res://skill_node/addons/defs/explosive_barrel_addon.tscn")
const _EXPLOSIVE := preload("res://effects/status/explosive.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_entity = autofree(Entity.new())
	_entity.display_name = "Bomber"
	_entity.stat_board = TestBoards.flat_entity_board()
	_entity.stat_board.xp.base_value = 100000.0
	# Past the first-turn upkeep skip, so one begin_turn() runs the upkeep.
	_entity.turns_taken = 1
	_graph.add_child(_entity)
	await get_tree().process_frame


func _node(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func _barrels(n: SkillNode, count: int) -> Array[ExplosiveBarrelAddon]:
	var out: Array[ExplosiveBarrelAddon] = []
	for i in count:
		var b := _BARREL_SCENE.instantiate() as ExplosiveBarrelAddon
		n.add_child(b)
		out.append(b)
	return out


func _charges(n: SkillNode) -> float:
	return n.get_combat().get_status_power(_EXPLOSIVE.id)


func _set_charges(n: SkillNode, target: float) -> void:
	var c := n.get_combat()
	c.remove_status(_EXPLOSIVE.id)
	if target > 0.0:
		c.apply_status(_EXPLOSIVE, target)


# --- acceptance 1: turn-start refill, allocated only --------------------------

func test_allocated_carrier_refills_to_its_barrel_count_at_turn_start() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 3)
	_set_charges(n, 1.0)
	assert_eq(_charges(n), 1.0, "arranged below the barrel count")
	_entity.begin_turn()
	assert_eq(_charges(n), float(barrels.size()), "N barrels refill to N")


func test_refill_never_overshoots_a_full_carrier() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 2)
	_set_charges(n, float(barrels.size()))
	_entity.begin_turn()
	assert_eq(_charges(n), float(barrels.size()), "already full: no barrel adds on top")


func test_unallocated_carrier_never_refills() -> void:
	# An unallocated node cannot host the CLEAR-on-dealloc charge at all, so
	# the spec's "stays at 1" reads "stays at what it has: none".
	var n := _node("Loose")
	var barrels := _barrels(n, 3)
	for b in barrels:
		b.on_turn_start()
	assert_eq(_charges(n), 0.0, "only an allocated carrier refills")


# --- acceptance 2: removal spends one charge -----------------------------------

func test_removing_a_barrel_spends_one_charge() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 2)
	_set_charges(n, 2.0)
	var before := _charges(n)
	n.remove_child(barrels[0])
	barrels[0].free()
	assert_eq(_charges(n), before - 1.0, "one barrel gone, one charge gone")


func test_removing_a_barrel_from_an_empty_carrier_stays_empty() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 2)
	assert_eq(_charges(n), 0.0, "arranged empty")
	n.remove_child(barrels[0])
	barrels[0].free()
	assert_eq(_charges(n), 0.0, "never below zero")


# --- acceptance 3: decay, then refill ------------------------------------------

func test_turn_end_decay_then_turn_start_refill() -> void:
	var n := _node("Carrier")
	_alloc.force_allocate(_entity, n)
	var barrels := _barrels(n, 3)
	_entity.begin_turn()
	var full := _charges(n)
	assert_eq(full, float(barrels.size()), "full after a turn start")
	n.get_combat().tick_statuses()
	var decayed := _charges(n)
	assert_lt(decayed, full, "turn-end decay spends a charge")
	_entity.begin_turn()
	assert_eq(_charges(n), full, "the next turn start refills what decayed")


# --- the temp face: one Explosive Status Stack on the swing's working copy ----
# A temp barrel is inert like any barrel; on apply it adds one stack to its
# vertex's `vertex_charges` (the swing's copy of the node's charges), and that
# stack is what the swing spends as a blast. The node's own row is untouched.

func _temp_barrels(n: SkillNode, count: int) -> Array[ExplosiveBarrelAddon]:
	var out: Array[ExplosiveBarrelAddon] = []
	for i in count:
		var b := _BARREL_SCENE.instantiate() as ExplosiveBarrelAddon
		b.is_temporary = true
		n.add_child(b)
		out.append(b)
	return out


## A two-vertex blade over [pivot, member], filled the way a swing fills it.
func _filled(pivot: SkillNode, member: SkillNode) -> BladeState:
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(80, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var state := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [pivot, member]
	BladeVertexFill.new().fill(state, nodes)
	return state


func test_a_temp_barrel_adds_one_stack_to_its_vertex() -> void:
	var pivot := _node("Pivot")
	var member := _node("Member")
	_alloc.force_allocate(_entity, member)
	_set_charges(member, 2.0)
	_temp_barrels(member, 1)
	var state := _filled(pivot, member)
	assert_eq(state.vertex_charges[1], int(_charges(member)) + 1, "live charges + 1")
	assert_eq(state.vertex_charges[0], 0, "the pivot carries none")


func test_two_temp_barrels_add_two_stacks() -> void:
	var pivot := _node("Pivot")
	var member := _node("Member")
	_alloc.force_allocate(_entity, member)
	_set_charges(member, 1.0)
	_temp_barrels(member, 2)
	assert_eq(_filled(pivot, member).vertex_charges[1], int(_charges(member)) + 2)


func test_a_map_barrel_adds_nothing_past_the_live_charges() -> void:
	var pivot := _node("Pivot")
	var member := _node("Member")
	_alloc.force_allocate(_entity, member)
	_barrels(member, 1)
	_set_charges(member, 1.0)
	assert_eq(_filled(pivot, member).vertex_charges[1], int(_charges(member)),
			"a map barrel's stacks are already the node's status")


func test_a_temp_barrel_never_writes_the_carriers_status_nor_counts_as_a_barrel() -> void:
	var pivot := _node("Pivot")
	var member := _node("Member")
	_alloc.force_allocate(_entity, member)
	var map := _barrels(member, 1)
	_set_charges(member, 1.0)
	var before := _charges(member)
	_temp_barrels(member, 1)
	_filled(pivot, member)
	assert_eq(_charges(member), before, "the carrier's explosive row is never written")
	assert_eq(map[0].barrel_count(), 1, "barrel_count skips the temp")


func test_a_swing_spends_a_temp_barrels_stack_as_exactly_one_blast() -> void:
	var f := await VolleyBoardFixture.build(self, true)
	var piece := f.leaves[0]
	assert_eq(piece.get_combat().get_status_power(_EXPLOSIVE.id), 0.0, "no live charges")
	_temp_barrels(piece, 1)
	var positions: Array[Vector2] = [Vector2(-400, 0), Vector2(430, 0)]
	var radii: Array[float] = [16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1)]
	var state := BladeState.build(positions, 0, edges, radii)
	var nodes: Array[SkillNode] = [f.hub, piece]
	BladeVertexFill.new().fill(state, nodes)
	assert_eq(state.vertex_charges[1], 1, "the temp's one stack is the piece's only charge")
	var gate := BladePopResolver.LiveGate.new(state, f.attacker)
	var ev := BladeHitEvent.new(0.5, 1, -1, f.target)
	var di := BladeDamageInstance.new(ev, gate)
	di.amount = 10.0
	di.type = DamageInstance.Type.PHYSICAL
	di.target = f.target
	di.attacker = f.attacker
	var hits: Array[HitInstance] = []
	gate.arm_blasts(ev, di, hits, CombatWorld.live(), [])
	gate.admit(ev, CombatWorld.live())
	assert_eq(gate.blast_of(ev), BladePopResolver.LiveGate.BLAST, "the contact set the blast off")
	assert_eq(state.vertex_charges[1], 0, "the stack is spent")
	var spends := gate.take_spends()
	assert_eq(spends.size(), 1, "exactly one spend")
	assert_eq(piece.get_combat().get_status_power(_EXPLOSIVE.id), 0.0,
			"nothing reached the board's status rows")
