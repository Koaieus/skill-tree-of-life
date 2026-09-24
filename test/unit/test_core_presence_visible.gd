extends GutTest

## [member SkillNode.core_presence_visible]: a bench knob that drops a core's
## presence dressing while leaving it a core for every gameplay rule.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _node: SkillNode
var _entity: Entity


func before_each() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(_node)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	_entity = Entity.new()
	_entity.stat_board = TestBoards.flat_entity_board()
	graph.entities_container.add_child(_entity)
	await get_tree().process_frame
	alloc.force_allocate(_entity, _node)
	_entity.core_location = _node


func _presence() -> Node:
	return _node.get_node("Visuals/NodeVisualsComposite").get_node("%CorePresence")


func test_a_core_shows_its_presence_by_default() -> void:
	assert_true(_presence().visible, "default: the core's presence is drawn")


func test_hiding_presence_keeps_the_node_a_core() -> void:
	_node.core_presence_visible = false
	assert_false(_presence().visible, "knob off: no core presence")
	assert_true(_node.is_core(), "still its owner's core for gameplay")


func test_hiding_survives_a_core_refresh() -> void:
	_node.core_presence_visible = false
	_entity.core_location = null
	_entity.core_location = _node
	assert_false(_presence().visible, "a core re-assignment must not re-show it")


func test_re_showing_restores_presence() -> void:
	_node.core_presence_visible = false
	_node.core_presence_visible = true
	assert_true(_presence().visible, "knob back on: presence drawn again")
