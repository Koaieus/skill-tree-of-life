@tool
extends GutTest

## ChannelLassoDirector bookkeeping: one lasso per channelling node, driven by
## a real AllocationSystem's stake / cancel / leash / ownership verbs; an abort
## (never a landing) plays one GateRope snap. Board as test_stake_channel.gd:
##   N0 (0, 0) - N1 (0.4, 0) - N2 (0.8, 0) - N3 (3, 0)   (units of R, core N0)
##   N4 (0, 1.2) off N0, N5 (0, -0.4) leaf off N0

const _DIRECTOR_SCENE := preload("res://ui/vfx/channel_lasso/channel_lasso_director.tscn")
const R := 250.0
const _POS := [Vector2(0, 0), Vector2(0.4, 0), Vector2(0.8, 0), Vector2(3, 0),
		Vector2(0, 1.2), Vector2(0, -0.4)]

var _w: TestWorld
var _graph: Graph
var _alloc: AllocationSystem
var _player: Entity
var _nodes: Array[SkillNode]
var _director: ChannelLassoDirector


func before_each() -> void:
	_w = TestWorld.create(self)
	_graph = _w.graph
	_nodes = []
	for i in _POS.size():
		_nodes.append(_w.add_node(StringName("N%d" % i), (_POS[i] as Vector2) * R))
	_w.link(_nodes[0], _nodes[1])
	_w.link(_nodes[1], _nodes[2])
	_w.link(_nodes[2], _nodes[3])
	_w.link(_nodes[0], _nodes[4])
	_w.link(_nodes[0], _nodes[5])

	_alloc = _w.allocator()
	_alloc.stake_reach_px = R
	_alloc.stake_leash_ratio = 2.0
	_alloc.stake_channel_turns = 2
	_alloc.extract_channel_turns = 3

	_player = _w.add_entity("Player", TestBoards.flat_entity_board())
	await get_tree().process_frame

	for n in _nodes:
		_alloc.force_allocate(_player, n)
	_player.core_location = _nodes[0]
	_player.stat_board.movement_points.base_value = 9.0
	_player.stat_board.movement_points.restore_to_full()

	_director = _DIRECTOR_SCENE.instantiate() as ChannelLassoDirector
	_director.allocation_system = _alloc
	_graph.add_child(_director)


func after_each() -> void:
	_graph = null
	_alloc = null
	_player = null
	_nodes = []
	_director = null


func _ticks(n: int) -> void:
	for i in n:
		_alloc.advance_channels(_player)


func _snaps() -> int:
	var count := 0
	for child in _director.get_children():
		if child is GateRope and not child.is_queued_for_deletion():
			count += 1
	return count


# --- 1. a stake creates one lasso; a raise keeps one -----------------------------

func test_stake_creates_one_lasso_and_a_raise_keeps_one() -> void:
	_director.initialize()
	var n := _nodes[1]
	assert_true(_alloc.stake(n, _player))
	assert_eq(_director.lasso_count(), 1, "one lasso on stake")
	assert_true(_director.has_lasso(n))
	assert_true(_alloc.stake(n, _player), "raise mid-channel")
	assert_eq(_director.lasso_count(), 1, "still one after the raise")


# --- 2. a landing frees with no snap; every abort frees with one snap ------------

func test_landed_final_step_frees_with_no_snap() -> void:
	_director.initialize()
	var n := _nodes[1]
	assert_true(_alloc.stake(n, _player))
	_ticks(_alloc.stake_channel_turns)
	assert_false(n.is_channelling(), "landed")
	assert_eq(_director.lasso_count(), 0)
	assert_false(_director.has_lasso(n))
	assert_eq(_snaps(), 0, "a landing never snaps")


func test_cancel_frees_and_snaps_once() -> void:
	_director.initialize()
	var n := _nodes[1]
	assert_true(_alloc.stake(n, _player))
	assert_true(_alloc.cancel_channel(n, _player))
	assert_eq(_director.lasso_count(), 0)
	assert_eq(_snaps(), 1)


func test_leash_break_frees_and_snaps_once() -> void:
	_director.initialize()
	var n := _nodes[1]
	assert_true(_alloc.stake(n, _player))
	assert_true(_alloc.move_core(_player, _nodes[1]))
	assert_true(_alloc.move_core(_player, _nodes[2]))
	assert_eq(_director.lasso_count(), 1, "inside the leash it stays")
	assert_true(_alloc.move_core(_player, _nodes[3]))
	assert_false(n.is_channelling(), "leash broke")
	assert_eq(_director.lasso_count(), 0)
	assert_eq(_snaps(), 1)


func test_ownership_loss_frees_and_snaps_once() -> void:
	_director.initialize()
	var n := _nodes[5]
	assert_true(_alloc.stake(n, _player))
	_alloc.force_deallocate(n)
	assert_null(n.owned_by)
	assert_eq(_director.lasso_count(), 0)
	assert_eq(_snaps(), 1)


# --- 3. rebuild adopts channels it never saw start -----------------------------

func test_rebuild_yields_one_lasso_per_channelling_node() -> void:
	assert_true(_alloc.stake(_nodes[1], _player))
	assert_true(_alloc.stake(_nodes[5], _player))
	assert_eq(_director.lasso_count(), 0, "not initialized: no signal seen")
	_director.initialize()
	assert_eq(_director.lasso_count(), 2, "initialize rebuilds")
	assert_true(_director.has_lasso(_nodes[1]))
	assert_true(_director.has_lasso(_nodes[5]))
	for i in [0, 2, 3, 4]:
		assert_false(_director.has_lasso(_nodes[i]), "N%d idles" % i)
	_director.rebuild()
	assert_eq(_director.lasso_count(), 2, "rebuild is idempotent")
