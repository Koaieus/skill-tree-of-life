extends GutTest

## A gate fuse whose blade edge hangs off a vertex that is already dead severs
## nothing. [method BladeState.remove_vertex] marks every incident edge in
## [member BladeState.removed_edges], and [method SwingResolve._fire_fuse] skips
## an edge [method BladeState.is_edge_removed] already reports — so the fuse
## records no `severed_at` and no Pop for it. The real gate still flips.
##
## Board, all owned by the attacker, core = Pivot:
##   Pivot – B1 =G1= B2 – B3        (G1 an open gate on B1–B2)

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _SPACING := 150.0
const _FUSE_FRAC := 0.5

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _attacker: Entity
var _n: Dictionary = {}
var _g1: Gate


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	_n[nm] = sn
	return sn


func before_each() -> void:
	_n = {}
	_graph = TestWorld.create(self).graph
	_alloc = TestWorld.allocator_for(_graph)
	_alloc.navigator = _graph.navigator
	_tm = autofree(TurnManager.new())
	add_child(_tm)
	_alloc.turn_manager = _tm

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	_attacker.stat_board.blade_size.base_value = 5.0
	_attacker.stat_board.action_points.base_value = 4.0
	_attacker.stat_board.action_points.current = 4.0
	_attacker.turns_taken = 1
	_graph.entities_container.add_child(_attacker)
	_tm.start_turn(_attacker)

	_spawn("Pivot", Vector2.ZERO)
	_spawn("B1", Vector2(_SPACING, 0.0))
	_spawn("B2", Vector2(_SPACING * 2.0, 0.0))
	_spawn("B3", Vector2(_SPACING * 3.0, 0.0))
	_graph.add_edge(_n["Pivot"], _n["B1"])
	_graph.add_edge(_n["B2"], _n["B3"])
	_g1 = _graph.add_gate(_n["B1"], _n["B2"], true)

	await get_tree().process_frame
	await get_tree().physics_frame

	for id in ["Pivot", "B1", "B2", "B3"]:
		_alloc.force_allocate(_attacker, _n[id])
	_attacker.core_location = _n["Pivot"]


func _plan() -> MeleeAttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _n["Pivot"]
	var blade: Array[SkillNode] = [_n["B1"], _n["B2"], _n["B3"]]
	plan.blade_nodes = blade
	return plan


## The blade edge index for B1–B2 and B2's vertex, in [param state]'s own lists.
func _b1_b2(state: BladeState) -> Vector2i:
	var b2 := 2  # selection order: Pivot, B1, B2, B3
	for i in state.edges.size():
		var e := state.edges[i]
		if (e.x == 1 and e.y == b2) or (e.x == b2 and e.y == 1):
			return Vector2i(i, b2)
	return Vector2i(-1, b2)


## Resolve the fused swing on a shadow, B2 killed first when [param kill_b2].
func _run(kill_b2: bool) -> Dictionary:
	var plan := _plan()
	assert_true(plan.is_valid(), "fixture: the plan must be valid")
	var world := CombatWorld.shadow()
	var ctx := plan.swing_context(world)
	var ids := _b1_b2(ctx.state)
	assert_gt(ids.x, -1, "fixture: B1–B2 is a blade edge")
	if kill_b2:
		assert_true(ctx.state.remove_vertex(ids.y), "B2 dies before the fuse")
	var run := SwingResolve.new(ctx)
	run.arm_fuse(_g1, _FUSE_FRAC, ids.x)
	run.advance(0)
	var fuse_pops := 0
	for pop in run.result.pops.pops:
		if pop.particle_idx < 0 and pop.edge_idx == ids.x:
			fuse_pops += 1
	var out := {
		"edge_removed": ctx.state.is_edge_removed(ids.x),
		"severed": run.result.pops.severed_at.has(ids.x),
		"fuse_pops": fuse_pops,
		"flips": run.result.gate_flips.size(),
	}
	world.free_shadow()
	return out


func test_a_live_edge_is_severed_by_its_fuse() -> void:
	var r := _run(false)
	assert_true(r.severed, "control: the fuse records severed_at on a live edge")
	assert_eq(r.fuse_pops, 1, "control: the fuse records one edge pop")
	assert_eq(r.flips, 1, "the real gate flips")


func test_a_fuse_on_an_edge_whose_vertex_died_severs_nothing() -> void:
	var r := _run(true)
	assert_true(r.edge_removed, "remove_vertex marked the incident edge removed")
	assert_false(r.severed, "the fuse records no severed_at for a dead vertex's edge")
	assert_eq(r.fuse_pops, 0, "the fuse records no edge pop for it")
	assert_eq(r.flips, 1, "the real gate still flips")
