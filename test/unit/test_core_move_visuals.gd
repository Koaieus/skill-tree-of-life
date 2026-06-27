extends GutTest

## Core-move visuals (#21 step 5/6 support): the reachability + path helpers on
## AllocationSystem that drive the CoreMoveHighlightProvider and the drag commit.
##
## Graph: a 4-node line A–B–C–D plus a self-loop on B (which must never count as
## a neighbour). Player owns all four; core starts at A.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _player: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)

	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])
	_add_edge(_nodes[2], _nodes[3])
	_add_edge(_nodes[1], _nodes[1])  # self-loop — never a neighbour

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_player)
	await get_tree().process_frame

	# Own through the system so the EntityNavigator mirror (which the reachability
	# / path helpers read) stays in sync — direct owned_by writes would drift it.
	for n in _nodes:
		_alloc.force_allocate(_player, n)
	_player.core_location = _nodes[0]


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := Edge.new()
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


func _set_mp(n: int) -> void:
	# Raise the cap (base_value), not just current — deplete() clamps to the cap,
	# so a multi-hop commit needs the cap high enough to spend each hop.
	_player.stat_board.movement_points.base_value = float(n)
	_player.stat_board.movement_points.restore_to_full()


# ── reachable_core_landings ────────────────────────────────────────────────

func test_reachable_one_hop_only_adjacent() -> void:
	_set_mp(1)
	var reach := _alloc.reachable_core_landings(_player, 1)
	assert_eq(reach.size(), 1, "budget 1 from A should reach only B")
	assert_true(reach.has(_nodes[1]), "B is the only 1-hop landing")
	assert_eq(int(reach[_nodes[1]]), 1)


func test_reachable_multi_hop_with_distances() -> void:
	var reach := _alloc.reachable_core_landings(_player, 3)
	assert_eq(reach.size(), 3, "budget 3 from A reaches B, C, D")
	assert_eq(int(reach[_nodes[1]]), 1, "B is 1 hop")
	assert_eq(int(reach[_nodes[2]]), 2, "C is 2 hops")
	assert_eq(int(reach[_nodes[3]]), 3, "D is 3 hops")


func test_reachable_excludes_core_itself() -> void:
	var reach := _alloc.reachable_core_landings(_player, 3)
	assert_false(reach.has(_nodes[0]), "the core slot is never its own landing")


func test_reachable_excludes_self_loop() -> void:
	_player.core_location = _nodes[1]
	var reach := _alloc.reachable_core_landings(_player, 1)
	assert_false(reach.has(_nodes[1]), "B's self-loop must not list B as reachable from B")
	assert_true(reach.has(_nodes[0]) and reach.has(_nodes[2]), "B reaches A and C")


func test_reachable_caps_at_budget() -> void:
	var reach := _alloc.reachable_core_landings(_player, 2)
	assert_false(reach.has(_nodes[3]), "D (3 hops) is excluded at budget 2")
	assert_true(reach.has(_nodes[2]), "C (2 hops) is included at budget 2")


func test_reachable_stops_at_unowned_node() -> void:
	_alloc.force_deallocate(_nodes[2])  # C unowned: severs the owned path past B
	var reach := _alloc.reachable_core_landings(_player, 5)
	assert_true(reach.has(_nodes[1]), "B still reachable")
	assert_false(reach.has(_nodes[2]), "unowned C is not a landing")
	assert_false(reach.has(_nodes[3]), "D unreachable once C (unowned) breaks the path")


# ── core_path ──────────────────────────────────────────────────────────────

func test_core_path_returns_inclusive_route() -> void:
	_set_mp(3)
	var path := _alloc.core_path(_player, _nodes[2])
	assert_eq(path, [_nodes[0], _nodes[1], _nodes[2]], "A→C path is A,B,C inclusive")


func test_core_path_empty_when_over_budget() -> void:
	_set_mp(2)
	var path := _alloc.core_path(_player, _nodes[3])  # needs 3 hops
	assert_eq(path.size(), 0, "A→D over a 2-MP budget yields no path")


func test_core_path_empty_for_unowned_target() -> void:
	_set_mp(5)
	_alloc.force_deallocate(_nodes[3])
	var path := _alloc.core_path(_player, _nodes[3])
	assert_eq(path.size(), 0, "unowned target yields no path")


# ── multi-hop commit (walk the path with move_core) ────────────────────────

func test_multi_hop_commit_lands_and_spends() -> void:
	_set_mp(3)
	var mp_before := int(_player.stat_board.movement_points.current)
	var path := _alloc.core_path(_player, _nodes[3])
	assert_eq(path.size(), 4, "A→D is a 4-node path at budget 3")
	for i in range(1, path.size()):
		assert_true(_alloc.move_core(_player, path[i]), "each hop along the path commits")
	assert_eq(_player.core_location, _nodes[3], "core ends on the target")
	assert_eq(int(_player.stat_board.movement_points.current), mp_before - 3,
			"a 3-hop move spends 3 MP")
