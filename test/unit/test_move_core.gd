extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Core movement (#21). `AllocationSystem.move_core` hops an entity's
## `core_location` along an adjacent edge over an owned subgraph, spends
## 1 movement_points, and emits `core_moved` for slide-tween VFX.
##
## These tests run on an in-memory Graph: a 4-node line A–B–C–D plus a
## stray edge A–D (the "long" jump that should fail), and a self-loop on B
## (which must never count as adjacency).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _player: Entity
var _nodes: Array[SkillNode]
var _core_moved_events: Array = []


func before_each() -> void:
	_core_moved_events = []

	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)

	# Line A–B, B–C, C–D plus stray A–D and a self-loop on B.
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])
	_add_edge(_nodes[2], _nodes[3])
	_add_edge(_nodes[1], _nodes[1])  # self-loop — never a valid landing

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_player)

	await get_tree().process_frame

	# Player owns A–B–C–D (the long-jump test wants A and D both owned).
	for n in _nodes:
		n.owned_by = _player
	_player.core_location = _nodes[0]

	_alloc.core_moved.connect(func(e: Entity, frm: SkillNode, to: SkillNode) -> void:
		_core_moved_events.append([e, frm, to]))


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _mp() -> PoolStat:
	return _player.stat_board.movement_points


# ── can_move_core ──────────────────────────────────────────────────────────

func test_adjacent_owned_target_is_movable() -> void:
	assert_true(_alloc.can_move_core(_player, _nodes[1]),
			"A→B (adjacent, owned) should be movable")


func test_non_adjacent_target_rejected() -> void:
	assert_false(_alloc.can_move_core(_player, _nodes[2]),
			"A→C (non-adjacent via owned graph) should be rejected")


func test_self_loop_landing_rejected() -> void:
	# Even though there's a B→B edge in the graph, a no-op land (target ==
	# current core) must be rejected — the move spends MP and the user gets
	# nothing back.
	_player.core_location = _nodes[1]
	assert_false(_alloc.can_move_core(_player, _nodes[1]),
			"B→B (self-loop landing) should be rejected even when an edge exists")


func test_stray_long_edge_does_not_count_when_intermediate_owned() -> void:
	# Just to clarify the contract: A–D is a real edge in our setup (stray
	# long jump), so A→D *is* adjacent. Document that explicitly so a future
	# graph rewrite doesn't silently change the answer.
	_add_edge(_nodes[0], _nodes[3])
	assert_true(_alloc.can_move_core(_player, _nodes[3]),
			"A→D becomes adjacent once the A–D edge exists")


func test_unowned_target_rejected() -> void:
	_nodes[1].owned_by = null
	assert_false(_alloc.can_move_core(_player, _nodes[1]),
			"target not owned by the entity must reject")


func test_zero_mp_rejected() -> void:
	_mp().deplete(int(_mp().current))
	assert_false(_alloc.can_move_core(_player, _nodes[1]),
			"zero MP must reject even on a valid landing")


func test_surplus_only_budget_allows_move() -> void:
	# #152: current MP drained to 0 but a transient surplus of 1 — the gate reads
	# available() (current + surplus), so the move is allowed and spends surplus
	# first (burn-it-or-lose-it), leaving current untouched at 0.
	var mp := _mp() as SurplusPoolStat
	mp.deplete(int(mp.current))  # current -> 0
	mp.set_surplus(1)
	assert_eq(mp.current, 0.0, "precondition: no ordinary MP")
	assert_true(_alloc.can_move_core(_player, _nodes[1]),
			"surplus alone must satisfy the move gate")
	assert_true(_alloc.move_core(_player, _nodes[1]), "move should commit on surplus budget")
	assert_eq(mp.surplus, 0, "surplus is spent first")
	assert_eq(mp.current, 0.0, "ordinary MP untouched — the surplus covered the hop")


func test_exhausted_surplus_then_rejects() -> void:
	var mp := _mp() as SurplusPoolStat
	mp.deplete(int(mp.current))
	mp.set_surplus(1)
	assert_true(_alloc.move_core(_player, _nodes[1]))  # spends the 1 surplus
	# Core is now on N1; a further hop has no budget (current 0, surplus 0).
	assert_false(_alloc.can_move_core(_player, _nodes[2]),
			"once surplus is burned and current is 0, further moves reject")


# ── move_core side effects ────────────────────────────────────────────────

func test_move_core_commits_location_and_spends_mp() -> void:
	var mp_before: int = int(_mp().current)
	var ok: bool = _alloc.move_core(_player, _nodes[1])
	assert_true(ok, "move_core should succeed on adjacent owned target")
	assert_eq(_player.core_location, _nodes[1], "core_location should update to target")
	assert_eq(int(_mp().current), mp_before - 1, "1 MP should be spent per hop")


func test_move_core_emits_core_moved_with_from_and_to() -> void:
	var ok: bool = _alloc.move_core(_player, _nodes[1])
	assert_true(ok)
	assert_eq(_core_moved_events.size(), 1, "core_moved should fire exactly once")
	var ev: Array = _core_moved_events[0]
	assert_eq(ev[0], _player)
	assert_eq(ev[1], _nodes[0], "from_node should be the previous core slot")
	assert_eq(ev[2], _nodes[1], "to_node should be the new core slot")


func test_move_core_failure_emits_nothing_and_spends_nothing() -> void:
	var mp_before: int = int(_mp().current)
	var ok: bool = _alloc.move_core(_player, _nodes[2])  # non-adjacent
	assert_false(ok)
	assert_eq(_player.core_location, _nodes[0], "core_location must not change on failure")
	assert_eq(int(_mp().current), mp_before, "MP must not be spent on failure")
	assert_eq(_core_moved_events.size(), 0, "core_moved must not fire on failure")


func test_owned_subgraph_unchanged_after_move() -> void:
	# No cut-vertex panic: the owned subgraph is identical before and after a
	# core hop. Verifies the "no cut-vertex check needed" reasoning in the plan.
	var owned_before: Array = []
	for n in _graph.get_skill_nodes():
		if n.owned_by == _player:
			owned_before.append(n)
	_alloc.move_core(_player, _nodes[1])
	var owned_after: Array = []
	for n in _graph.get_skill_nodes():
		if n.owned_by == _player:
			owned_after.append(n)
	assert_eq(owned_after, owned_before, "ownership set must not change on a core hop")
