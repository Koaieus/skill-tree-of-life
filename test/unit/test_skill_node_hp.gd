extends GutTest

## SkillNode combat HP invariant across allocation cycles — node_board.health
## PoolStat replaces the old current_hp float + get_max_hp LocalStat routing.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


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
	_entity.display_name = "Cycler"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_graph.add_child(_entity)

	await get_tree().process_frame  # entity._ready


func _hp_pool() -> PoolStat:
	return _node.node_board.get_stat(&"node_health") as PoolStat if _node.node_board != null else null


func test_current_hp_full_on_first_allocation() -> void:
	_alloc.force_allocate(_entity, _node)
	var hp := _hp_pool()
	assert_not_null(hp, "combat health pool should exist after allocation")
	var maxv: float = hp.value
	assert_gt(maxv, 0.0, "node_health max should be positive when owned")
	assert_almost_eq(hp.current, maxv, 0.001,
			"freshly allocated node should be at full HP")


func test_current_hp_refills_after_realloc_cycle() -> void:
	_alloc.force_allocate(_entity, _node)
	_alloc.force_deallocate(_node)
	assert_eq(_node.owned_by, null, "node should be unowned after dealloc")
	var hp := _hp_pool()
	assert_almost_eq(hp.current, 0.0, 0.001, "unowned node has no HP")

	_alloc.force_allocate(_entity, _node)
	hp = _hp_pool()
	var maxv: float = hp.value
	assert_gt(maxv, 0.0, "re-allocated node_health max should be positive")
	assert_almost_eq(hp.current, maxv, 0.001,
			"re-allocated node must refill to full")


func test_realloc_reads_modified_max_not_stale_default() -> void:
	var nh := _entity.stat_board.get_stat(&"node_health")
	var m := StatModifier.new()
	m.stat_id = &"node_health"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = 40.0
	nh.add_modifier(m)

	_alloc.force_allocate(_entity, _node)
	var hp := _hp_pool()
	assert_almost_eq(hp.value, 50.0, 0.001, "modified max should be 50")
	assert_almost_eq(hp.current, 50.0, 0.001, "alloc refilled to 50")

	_alloc.force_deallocate(_node)
	_alloc.force_allocate(_entity, _node)
	hp = _hp_pool()
	assert_almost_eq(hp.current, 50.0, 0.001,
			"re-alloc must refill to the MODIFIED max (50), not stale (#92)")


func test_multiple_cycles_stay_full() -> void:
	for i in 4:
		_alloc.force_allocate(_entity, _node)
		var hp := _hp_pool()
		var maxv: float = hp.value
		assert_almost_eq(hp.current, maxv, 0.001,
				"cycle %d: node should be full after allocate" % i)
		_alloc.force_deallocate(_node)
