extends GutTest
## #916 — a pre-staked Dormant Core: `GameRoot.spawn_blocker(..., stake_level)`
## stamps the cap, fills it through `force_fill` (no SP minted for the fill),
## offsets the kill XP by a clamped MULTIPLY read off the blocker's own board,
## and the node it leaves behind on a kill is a 0/3 a player can fill.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _NODE_SCENE := preload("res://skill_node/blocker_node.tscn")
const _EDGE_SCENE := preload("res://graph/edge.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _root: GameRoot
var _nodes: Array[SkillNode] = []


func before_each() -> void:
	_graph = autofree(_GRAPH_SCENE.instantiate()) as Graph
	add_child(_graph)
	await get_tree().process_frame
	_nodes.clear()
	var previous: SkillNode = null
	for i in 3:
		var node: SkillNode = _NODE_SCENE.instantiate()
		node.name = "N%d" % i
		node.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(node)
		if previous != null:
			var e := _EDGE_SCENE.instantiate() as Edge
			e.from = previous
			e.to = node
			_graph.edges_container.add_child(e)
		previous = node
		_nodes.append(node)
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	_root = GameRoot.new()
	autofree(_root)
	_root.graph = _graph
	_root.allocation_system = _alloc
	await get_tree().process_frame


func after_each() -> void:
	_nodes.clear()
	_graph = null
	_alloc = null
	_root = null


func _spawn(stake: int) -> Entity:
	var ent := _root.spawn_blocker(GameRoot.BlockerSize.SMALL, _nodes[1],
			[_nodes[2]] as Array[SkillNode], 0, 0.0, 0, stake)
	return ent


## The offset the spec pins (owner verbatim on #784), computed from the board
## the blocker actually spawned with — no literal numbers.
func _expected_offset(board: EntityStatBoard, stake: int, floor_: float) -> float:
	# `Stat.value` is Variant-typed: cast both, or 5 / 2 is an integer 2.
	var xp_per_sp: float = float(board.xp.value) / float(board.sp_gain_on_levelup.value)
	return clampf(1.0 - float(stake - 1) * xp_per_sp / board.core_kill_xp.base_value, floor_, 1.0)


func test_stake_3_spawns_filled_with_local_modifiers_at_x3() -> void:
	var m := StatModifier.new()
	m.stat_id = &"strength"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 1.0
	_nodes[1].modifiers = [m]
	var blocker := _spawn(3)
	var node := _nodes[1]
	assert_eq(node.owned_by, blocker)
	assert_eq(node.stake_level, 3, "cap stamped")
	assert_eq(node.allocation_level, 3, "filled to the cap while alive")
	var base_str: float = blocker.stat_board.get_stat(&"strength").base_value
	assert_eq(blocker.stat_board.get_stat(&"strength").get_value(), base_str + 3.0,
			"the core's local modifier lands x3")
	assert_eq(_nodes[2].stake_level, 1, "footprint nodes are not staked")
	assert_eq(_nodes[2].allocation_level, 1)
	assert_eq(blocker.stat_board.skill_points.used, 2,
			"one SP claimed per owned node, none for the fill")


func test_stake_1_is_the_plain_blocker() -> void:
	var blocker := _spawn(1)
	assert_eq(_nodes[1].stake_level, 1)
	assert_eq(_nodes[1].allocation_level, 1)
	var board := blocker.stat_board
	assert_eq(board.core_kill_xp.value, board.core_kill_xp.base_value,
			"stake 1: kill XP untouched")


func test_stake_3_offsets_kill_xp_by_the_clamped_multiply() -> void:
	var blocker := _spawn(3)
	var board := blocker.stat_board
	var expected := board.core_kill_xp.base_value * _expected_offset(board, 3, 0.25)
	assert_almost_eq(board.core_kill_xp.value, expected, 0.0001,
			"core_kill_xp = base x clamp(1 - (stake-1) * XP_PER_SP / base, floor, 1)")
	assert_lt(board.core_kill_xp.value, board.core_kill_xp.base_value,
			"a pre-stake always costs the killer some XP on the small board")


func test_killed_staked_blocker_leaves_a_0_of_3_a_player_can_fill() -> void:
	_spawn(3)
	var node := _nodes[1]
	_alloc.force_deallocate(node)
	_alloc.force_deallocate(_nodes[2])
	assert_null(node.owned_by, "kill: unowned")
	assert_eq(node.allocation_level, 0, "kill: fill emptied")
	assert_eq(node.stake_level, 3, "kill: the cap stays on the node")

	var player := Entity.new()
	player.display_name = "Player"
	player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(player)
	autofree(player)
	await get_tree().process_frame
	player.stat_board.skill_points.grant(3)
	assert_true(_alloc.allocate(node, player), "1/3")
	assert_true(_alloc.allocate(node, player), "2/3")
	assert_true(_alloc.allocate(node, player), "3/3")
	assert_false(_alloc.allocate(node, player), "full: a 4th allocate is refused")
	assert_eq(node.allocation_level, 3)
	assert_eq(node.owned_by, player)


func test_stake_never_exceeds_the_ceiling() -> void:
	_spawn(AllocationSystem.STAKE_CEILING + 2)
	assert_eq(_nodes[1].stake_level, AllocationSystem.STAKE_CEILING, "clamped to the ceiling")
	assert_eq(_nodes[1].allocation_level, AllocationSystem.STAKE_CEILING)
