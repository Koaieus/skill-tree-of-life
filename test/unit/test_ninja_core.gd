extends GutTest

## #39: the Ninja — high dealloc budget, low SP cap, and a bounded, very
## short-range core aura that makes nearby owned nodes hit harder. Reach is
## deliberately bounded (unlike the Serpent's unbounded auras): the Ninja is
## rewarded for staying compact, not for sprawling.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _NINJA := preload("res://entity/core/ninja_core.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _nodes: Array[SkillNode]
var _entity: Entity
## skill_points.claim(1) runs per force_allocate below, growing the pool cap by
## 1 per owned node — a fixture side effect, not a Ninja stat. Captured right
## after core_class.apply() so test_statline reads the class's own delta.
var _skill_points_before_allocation: float


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
	# A straight line: 0-1-2-3, so hop distance == chain index.
	_graph.add_edge(_nodes[0], _nodes[1])
	_graph.add_edge(_nodes[1], _nodes[2])
	_graph.add_edge(_nodes[2], _nodes[3])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_entity = autofree(Entity.new()) as Entity
	_entity.display_name = "Phantom"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_entity.core_class = _NINJA
	_graph.add_child(_entity)  # _ready → core_class.apply() grants modifiers + aura
	await get_tree().process_frame
	_skill_points_before_allocation = _entity.stat_board.skill_points.get_value()

	# Mirror GameRoot.spawn_entity's order: force_allocate the core node, THEN
	# assign core_location (the setter is what re-derives the aura — see
	# test_aura_effect.gd's test_core_class_aura_populates_via_the_spawn_entity_order).
	_alloc.force_allocate(_entity, _nodes[0])
	_entity.core_location = _nodes[0]
	_alloc.force_allocate(_entity, _nodes[1])
	_alloc.force_allocate(_entity, _nodes[2])
	_alloc.force_allocate(_entity, _nodes[3])


func test_statline() -> void:
	var b := _entity.stat_board
	assert_eq(b.strength.get_value(), 20.0, "10 base + 10 class")
	assert_eq(b.dexterity.get_value(), 20.0)
	assert_eq(b.intelligence.get_value(), 20.0)
	assert_eq(b.deallocation_points.get_value(), 5.0, "3 base + 2 class: fast reshaping")
	assert_eq(_skill_points_before_allocation, 2.0, "3 base - 1 class: stays compact")


## Isolates the aura's own contribution from the class's flat +10 strength
## baseline, which the local read still carries via entity-board pass-through.
func test_aura_is_intense_at_core_and_fades_to_zero_by_two_hops() -> void:
	var baseline: float = _entity.stat_board.strength.get_value()
	assert_almost_eq(_local_strength(_nodes[0]) - baseline, 6.0, 0.001, "core: full aura")
	assert_almost_eq(_local_strength(_nodes[1]) - baseline, 3.0, 0.001, "1 hop: half aura")
	assert_almost_eq(_local_strength(_nodes[2]) - baseline, 0.0, 0.001, "2 hops: scale hits zero")
	assert_almost_eq(_local_strength(_nodes[3]) - baseline, 0.0, 0.001, "3 hops: out of reach entirely")


## move_core only hops to an *adjacent* owned node (AllocationSystem's
## contract) — node0 → node1, not a multi-hop teleport.
func test_core_moving_drops_the_buff_on_nodes_left_behind() -> void:
	var baseline: float = _entity.stat_board.strength.get_value()
	assert_almost_eq(_local_strength(_nodes[2]) - baseline, 0.0, 0.001, "2 hops from the old core: out of reach")

	assert_true(_alloc.move_core(_entity, _nodes[1]), "adjacent move must succeed")

	assert_almost_eq(_local_strength(_nodes[1]) - baseline, 6.0, 0.001, "now the core")
	assert_almost_eq(_local_strength(_nodes[0]) - baseline, 3.0, 0.001, "1 hop from the new core: half aura")
	assert_almost_eq(_local_strength(_nodes[2]) - baseline, 3.0, 0.001, "1 hop from the new core: half aura")
	assert_almost_eq(_local_strength(_nodes[3]) - baseline, 0.0, 0.001, "2 hops from the new core: scale hits zero")


func _local_strength(n: SkillNode) -> float:
	return float(n.get_local_value(&"strength"))
