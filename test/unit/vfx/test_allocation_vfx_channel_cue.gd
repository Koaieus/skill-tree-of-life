extends GutTest
## AllocationVFX drives a channelling node's rim cue off AllocationSystem's
## channel signals: direction and fraction pushed to the node's composite on
## every change, progress tick, step and end.

const _Composite := preload("res://skill_node/visuals/node_visuals_composite.gd")
const R := 250.0

var _w: TestWorld
var _graph: Graph
var _alloc: AllocationSystem
var _vfx: AllocationVFX
var _player: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_w = TestWorld.create(self)
	_graph = _w.graph
	_nodes = []
	for i in 2:
		_nodes.append(_w.add_node(StringName("N%d" % i), Vector2(0.4 * i, 0) * R))
	_w.link(_nodes[0], _nodes[1])

	_alloc = _w.allocator()
	_alloc.stake_reach_px = R
	_alloc.stake_leash_ratio = 2.0
	_alloc.stake_channel_turns = 2

	_vfx = AllocationVFX.new()
	_vfx.allocation_system = _alloc
	_graph.add_child(_vfx)

	_player = _w.add_entity("Player", TestBoards.flat_entity_board())
	await get_tree().process_frame

	for n in _nodes:
		_alloc.force_allocate(_player, n)
	_player.core_location = _nodes[0]


func after_each() -> void:
	_graph = null
	_alloc = null
	_vfx = null
	_player = null
	_nodes = []


func _cue(n: SkillNode) -> _Composite:
	return n.node_visuals() as _Composite


func test_stake_lights_the_cue_and_ticks_deepen_it_until_it_lands() -> void:
	var n := _nodes[1]
	assert_true(_alloc.stake(n, _player), "stake opens a channel")
	assert_eq(_cue(n).channel_direction, 1, "channel_changed pushes the direction")
	assert_almost_eq(_cue(n).channel_fraction, 0.0, 0.001)
	_alloc.advance_channels(_player)
	assert_almost_eq(_cue(n).channel_fraction, 0.5, 0.001,
			"a non-landing tick refreshes the fraction")
	_alloc.advance_channels(_player)
	assert_eq(_cue(n).channel_direction, 0, "a landed channel clears the cue")
	assert_almost_eq(_cue(n).channel_fraction, 0.0, 0.001)
