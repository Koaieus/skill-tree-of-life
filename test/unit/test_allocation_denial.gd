@tool
extends GutTest

## The stake / extract gates name their own refusal: `stake_denial` /
## `extract_denial` return the `node_action_denied` reason key of the first
## gate that fails, `&""` when the action is allowed, and `can_*` is exactly
## "the denial is empty". Each fixture fails one gate, in gate order.
##
## Board: N0 (core) - N1 - N2 - N3, all owned; N4 hangs off N0, unowned.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _player: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 5:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	for i in 3:
		_graph.add_edge(_nodes[i], _nodes[i + 1])
	_graph.add_edge(_nodes[0], _nodes[4])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_player)
	await get_tree().process_frame

	for i in 4:
		_alloc.force_allocate(_player, _nodes[i])
	_player.core_location = _nodes[0]


func after_each() -> void:
	_graph = null
	_alloc = null
	_player = null
	_nodes = []


func _board() -> EntityStatBoard:
	return _player.stat_board


func _assert_stake(node: SkillNode, expected: StringName) -> void:
	var denial: StringName = _alloc.stake_denial(node, _player)
	assert_eq(denial, expected, "stake_denial on %s" % node.name)
	assert_eq(_alloc.can_stake(node, _player), denial == &"",
			"can_stake agrees with stake_denial on %s" % node.name)


func _assert_extract(node: SkillNode, expected: StringName) -> void:
	var denial: StringName = _alloc.extract_denial(node, _player)
	assert_eq(denial, expected, "extract_denial on %s" % node.name)
	assert_eq(_alloc.can_extract(node, _player), denial == &"",
			"can_extract agrees with extract_denial on %s" % node.name)


# --- stake ----------------------------------------------------------------------

func test_stake_allowed_is_empty() -> void:
	_assert_stake(_nodes[0], &"")
	_assert_stake(_nodes[1], &"")


func test_stake_not_owned() -> void:
	_assert_stake(_nodes[4], &"stake_denied_not_owned")


func test_stake_at_ceiling() -> void:
	_nodes[1].stake_level = AllocationSystem.STAKE_CEILING
	_assert_stake(_nodes[1], &"stake_denied_at_ceiling")


func test_stake_not_adjacent() -> void:
	_assert_stake(_nodes[2], &"stake_denied_not_adjacent")


func test_stake_no_sp() -> void:
	_board().skill_points.set_current(0.0)
	_assert_stake(_nodes[1], &"stake_denied_no_sp")


func test_stake_no_ap() -> void:
	_board().action_points.set_current(0.0)
	_assert_stake(_nodes[1], &"stake_denied_no_ap")


func test_stake_null_is_generic() -> void:
	assert_eq(_alloc.stake_denial(null, _player), &"stake_denied")
	assert_eq(_alloc.stake_denial(_nodes[0], null), &"stake_denied")
	assert_false(_alloc.can_stake(null, _player))
	assert_false(_alloc.can_stake(_nodes[0], null))


# --- extract --------------------------------------------------------------------

func test_extract_allowed_is_empty() -> void:
	assert_true(_alloc.stake(_nodes[1], _player))
	_assert_extract(_nodes[1], &"")


func test_extract_not_owned() -> void:
	assert_true(_alloc.stake(_nodes[1], _player))
	_nodes[4].stake_level = 2
	_assert_extract(_nodes[4], &"extract_denied_not_owned")


func test_extract_at_floor() -> void:
	assert_true(_alloc.stake(_nodes[1], _player))
	_assert_extract(_nodes[0], &"extract_denied_at_floor")


func test_extract_not_adjacent() -> void:
	assert_true(_alloc.stake(_nodes[1], _player))
	_nodes[2].stake_level = 2
	_assert_extract(_nodes[2], &"extract_denied_not_adjacent")


func test_extract_no_dp() -> void:
	assert_true(_alloc.stake(_nodes[1], _player))
	_board().deallocation_points.set_current(0.0)
	_assert_extract(_nodes[1], &"extract_denied_no_dp")


func test_extract_no_staked_sp() -> void:
	_nodes[1].stake_level = 2
	_assert_extract(_nodes[1], &"extract_denied_no_staked_sp")


func test_extract_null_is_generic() -> void:
	assert_eq(_alloc.extract_denial(null, _player), &"extract_denied")
	assert_eq(_alloc.extract_denial(_nodes[0], null), &"extract_denied")
	assert_false(_alloc.can_extract(null, _player))
	assert_false(_alloc.can_extract(_nodes[0], null))
