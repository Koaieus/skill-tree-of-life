extends GutTest

## #39: the Serpent — two auras riding the same `armor` stat, one keyed to hop
## distance (grows with topological distance) and one to euclidean distance
## (shrinks with spatial distance). `Array[Effect]` composes them without any
## `CompositeEffect` — see docs/domain/effect-system.md's Auras table.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SERPENT := preload("res://entity/core/serpent_core.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]
var _entity: Entity


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_nodes = []
	for i in 4:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		sn.position = Vector2(i * 100.0, 0.0)
		_graph.add_skill_node(sn)
		_nodes.append(sn)
	# A straight line, so hop distance (chain index) and euclidean distance
	# (100px per hop) both grow together from either end — exactly the
	# "same node, both metrics" case the class composes.
	_graph.add_edge(_nodes[0], _nodes[1])
	_graph.add_edge(_nodes[1], _nodes[2])
	_graph.add_edge(_nodes[2], _nodes[3])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new()) as Entity
	_entity.display_name = "Coil"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_entity.core_class = _SERPENT
	_graph.add_child(_entity)
	await get_tree().process_frame

	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]
	_alloc.force_allocate(_entity, _nodes[1])
	_alloc.force_allocate(_entity, _nodes[2])
	_alloc.force_allocate(_entity, _nodes[3])
	_entity.stat_board.armor.base_value = 0.0


func test_statline() -> void:
	var b := _entity.stat_board
	assert_eq(b.strength.get_value(), 20.0, "10 base + 10 class")
	assert_eq(b.dexterity.get_value(), 20.0)
	assert_eq(b.intelligence.get_value(), 20.0)


func test_dual_metric_auras_sum_on_the_same_stat() -> void:
	assert_almost_eq(_armor(_nodes[0]), 0.0, 0.001, "core: both scales are 0")
	# 1 hop / 100px: +1 hop buff, -0.5 euclid penalty.
	assert_almost_eq(_armor(_nodes[1]), 0.5, 0.001)
	# 2 hops / 200px: +2 hop buff, -1.0 euclid penalty.
	assert_almost_eq(_armor(_nodes[2]), 1.0, 0.001)


## move_core only hops to an *adjacent* owned node (AllocationSystem's
## contract) — node0 → node1, not a multi-hop teleport.
func test_core_move_recomputes_both_auras() -> void:
	assert_true(_alloc.move_core(_entity, _nodes[1]), "adjacent move must succeed")

	assert_almost_eq(_armor(_nodes[1]), 0.0, 0.001, "new core: untouched")
	assert_almost_eq(_armor(_nodes[0]), 0.5, 0.001, "1 hop / 100px from new core")
	assert_almost_eq(_armor(_nodes[2]), 0.5, 0.001, "1 hop / 100px on the other side")
	assert_almost_eq(_armor(_nodes[3]), 1.0, 0.001, "2 hops / 200px from new core")


func _armor(n: SkillNode) -> float:
	return float(n.get_local_value(&"armor"))
