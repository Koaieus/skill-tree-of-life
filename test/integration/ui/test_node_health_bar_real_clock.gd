extends GutTest

## The ONE real-clock run of the per-node [HealthBar] (the #147 keeper). Every
## fade and fill assert lives in `test/unit/test_node_health_bar.gd`, stepped
## through the bar's `clock`; this script is the single proof that the fade
## bookkeeping settles when the real frame loop moves the tweens.
##
## #147: force-deallocating a full-HP node zeroes its combat HP synchronously
## (a fade-IN) a frame before the deferred rebind to null (a fade-OUT); the bar
## must end faded out, with every tween it started finished.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode
var _bar: ProgressBar


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.name = "N0"
	_graph.skill_nodes_container.add_child(_node)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _node)
	await get_tree().process_frame
	_bar = _node.get_node("Visuals/HealthBar")


func test_full_hp_dealloc_settles_faded_out_on_the_real_clock() -> void:
	_alloc.force_deallocate(_node)
	await get_tree().process_frame  # flush deferred owner_changed → rebind to null
	await get_tree().process_frame
	var settled := func() -> bool:
		return _bar.clock.live_count() == 0 and _bar.modulate.a < 0.05
	assert_true(await wait_until(settled, 15.0),
			"a deallocated full-HP node settles faded out, no tween left running (#147)")
