extends GutTest

## Multi-hop allocation path + mass-deallocation cascade (see
## docs/domain/... mass-action confirm panel plan). Fixtures use
## `graph.add_skill_node`/`add_edge` (not raw container add_child) so
## `graph.navigator` — the GLOBAL mirror `allocation_path` routes over — is
## actually populated (`.claude/rules/graph.md`).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _player: Entity
var _enemy: Entity
var _nodes: Dictionary  # String -> SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = {}
	for id in ["A", "B", "C", "D", "E"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = id
		_graph.add_skill_node(sn)
		_nodes[id] = sn

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.navigator = _graph.navigator
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_player)

	_enemy = autofree(Entity.new())
	_enemy.display_name = "Enemy"
	_enemy.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_enemy)

	await get_tree().process_frame

	_alloc.force_allocate(_player, _nodes["A"])
	_player.core_location = _nodes["A"]


func _n(id: String) -> SkillNode:
	return _nodes[id]


func _add_edge(a: String, b: String) -> void:
	_graph.add_edge(_n(a), _n(b))


func _grant_sp(entity: Entity, n: int) -> void:
	entity.stat_board.skill_points.grant(n)


## Sets the entity's available DP to exactly [param n] — zeroes out the
## board's default starting DP (deallocation_points.tres ships with a nonzero
## base cap) before granting the surplus, so tests get the exact budget they ask for.
func _grant_dp(entity: Entity, n: int) -> void:
	var dp: SurplusPoolStat = entity.stat_board.deallocation_points
	dp.deplete(dp.available())
	dp.set_surplus(n)


# ── allocation_path ──────────────────────────────────────────────────────

func test_allocation_path_straight_line() -> void:
	_add_edge("A", "B")
	_add_edge("B", "C")
	_add_edge("C", "D")
	var path := _alloc.allocation_path(_player, _n("D"))
	assert_eq(path, [_n("A"), _n("B"), _n("C"), _n("D")], "fewest-hop straight route")


func test_allocation_path_already_owned_target_is_empty() -> void:
	_add_edge("A", "B")
	_alloc.force_allocate(_player, _n("B"))
	var path := _alloc.allocation_path(_player, _n("B"))
	assert_eq(path, [] as Array[SkillNode], "already-owned target has no route to offer")


func test_allocation_path_no_owned_frontier_is_empty() -> void:
	_add_edge("A", "B")
	var homeless := Entity.new()
	autofree(homeless)
	homeless.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(homeless)
	await get_tree().process_frame
	var path := _alloc.allocation_path(homeless, _n("B"))
	assert_eq(path, [] as Array[SkillNode], "no owned territory yet — nothing to route from")


func test_allocation_path_detours_around_enemy_owned_node() -> void:
	# A-B-D is blocked (enemy owns B); A-C-D is the detour.
	_add_edge("A", "B")
	_add_edge("B", "D")
	_add_edge("A", "C")
	_add_edge("C", "D")
	_alloc.force_allocate(_enemy, _n("B"))
	var path := _alloc.allocation_path(_player, _n("D"))
	assert_eq(path, [_n("A"), _n("C"), _n("D")], "routes around enemy territory")


func test_allocation_path_detours_around_unrevealed_node() -> void:
	# Same shape as the enemy-blocker case, but fog does the blocking.
	_add_edge("A", "B")
	_add_edge("B", "D")
	_add_edge("A", "C")
	_add_edge("C", "D")
	_n("B").revealed = false
	var path := _alloc.allocation_path(_player, _n("D"))
	assert_eq(path, [_n("A"), _n("C"), _n("D")], "routes around fogged territory")


func test_allocation_path_no_route_when_only_path_is_blocked() -> void:
	_add_edge("A", "B")
	_add_edge("B", "D")
	_alloc.force_allocate(_enemy, _n("B"))
	var path := _alloc.allocation_path(_player, _n("D"))
	assert_eq(path, [] as Array[SkillNode], "the only route is blocked — no detour exists")


# ── mass_allocate ────────────────────────────────────────────────────────

func test_mass_allocate_executes_full_affordable_path() -> void:
	_add_edge("A", "B")
	_add_edge("B", "C")
	_grant_sp(_player, 2)
	var path := _alloc.allocation_path(_player, _n("C"))
	var count := _alloc.mass_allocate(_player, path, 2)
	assert_eq(count, 2, "both new hops landed")
	assert_eq(_n("B").owned_by, _player)
	assert_eq(_n("C").owned_by, _player)


func test_mass_allocate_stops_at_affordable_prefix() -> void:
	_add_edge("A", "B")
	_add_edge("B", "C")
	_add_edge("C", "D")
	_grant_sp(_player, 2)
	var path := _alloc.allocation_path(_player, _n("D"))  # A-B-C-D, 3 new hops
	var affordable: int = mini(path.size() - 1, 2)
	var count := _alloc.mass_allocate(_player, path, affordable)
	assert_eq(count, 2, "only the SP-affordable prefix executes")
	assert_eq(_n("B").owned_by, _player)
	assert_eq(_n("C").owned_by, _player)
	assert_null(_n("D").owned_by, "past the affordable prefix — not allocated")


# ── deallocation_cascade / can_deallocate_set / deallocate_set ──────────

func test_deallocation_cascade_of_cut_vertex_includes_the_tail() -> void:
	_add_edge("A", "B")
	_add_edge("B", "C")
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var cascade := _alloc.deallocation_cascade(_n("B"), _player)
	assert_eq(cascade.size(), 2, "the cut vertex plus its stranded tail")
	assert_true(_n("B") in cascade)
	assert_true(_n("C") in cascade)


func test_deallocation_cascade_of_leaf_is_just_itself() -> void:
	_add_edge("A", "B")
	_alloc.force_allocate(_player, _n("B"))
	var cascade := _alloc.deallocation_cascade(_n("B"), _player)
	assert_eq(cascade, [_n("B")], "a leaf islands nobody")


func test_deallocation_cascade_of_core_is_empty() -> void:
	var cascade := _alloc.deallocation_cascade(_player.core_location, _player)
	assert_eq(cascade, [] as Array[SkillNode], "the core never enters a cascade")


func test_can_deallocate_set_gates_on_full_dp_budget() -> void:
	_add_edge("A", "B")
	_add_edge("B", "C")
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var cascade := _alloc.deallocation_cascade(_n("B"), _player)
	_grant_dp(_player, 1)
	assert_false(_alloc.can_deallocate_set(cascade, _player), "1 DP can't cover a 2-node cascade")
	_grant_dp(_player, 2)
	assert_true(_alloc.can_deallocate_set(cascade, _player), "2 DP covers it exactly")


func test_deallocate_set_is_all_or_nothing_on_insufficient_dp() -> void:
	_add_edge("A", "B")
	_add_edge("B", "C")
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var cascade := _alloc.deallocation_cascade(_n("B"), _player)
	_grant_dp(_player, 1)
	var ok := _alloc.deallocate_set(cascade, _player)
	assert_false(ok, "insufficient DP rejects the whole batch")
	assert_eq(_n("B").owned_by, _player, "no partial mutation on the target")
	assert_eq(_n("C").owned_by, _player, "no partial mutation on the tail")


func test_deallocate_set_takes_the_whole_cascade_with_enough_dp() -> void:
	_add_edge("A", "B")
	_add_edge("B", "C")
	_alloc.force_allocate(_player, _n("B"))
	_alloc.force_allocate(_player, _n("C"))
	var cascade := _alloc.deallocation_cascade(_n("B"), _player)
	_grant_dp(_player, cascade.size())
	var ok := _alloc.deallocate_set(cascade, _player)
	assert_true(ok)
	assert_null(_n("B").owned_by)
	assert_null(_n("C").owned_by)


func test_deallocate_set_refunds_sp_per_node_fill() -> void:
	_add_edge("A", "B")
	_alloc.force_allocate(_player, _n("B"))
	var sp_before: int = _player.stat_board.skill_points.available()
	var cascade: Array[SkillNode] = [_n("B")]
	_grant_dp(_player, 1)
	_alloc.deallocate_set(cascade, _player)
	var sp_after: int = _player.stat_board.skill_points.available()
	assert_eq(sp_after, sp_before + 1, "the node's fill (1) is refunded")
