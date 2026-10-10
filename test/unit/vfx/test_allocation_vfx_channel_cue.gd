extends GutTest
## AllocationVFX drives a channelling node's rim cue off AllocationSystem's
## channel signals: direction and fraction pushed to the node's composite on
## every change, progress tick, step and end.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _Composite := preload("res://skill_node/visuals/node_visuals_composite.gd")
const R := 250.0

var _graph: Graph
var _alloc: AllocationSystem
var _vfx: AllocationVFX
var _player: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_nodes = []
	for i in 2:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.add_skill_node(sn)
		sn.position = Vector2(0.4 * i, 0) * R
		_nodes.append(sn)
	_graph.add_edge(_nodes[0], _nodes[1])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	_alloc.stake_reach_px = R
	_alloc.stake_leash_ratio = 2.0
	_alloc.stake_channel_turns = 2
	add_child_autofree(_alloc)

	_vfx = AllocationVFX.new()
	_vfx.allocation_system = _alloc
	_graph.add_child(_vfx)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = TestBoards.flat_entity_board()
	_graph.add_child(_player)
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
