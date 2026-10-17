extends GutTest
## #915 — AllocationSystem.force_fill(node, level): the allocate-path primitive
## that fills an owned node beyond 1 without minting SP. Preconditions and the
## force_deallocate-from-filled property live here; the local-scale side of
## the walk (x3 modifiers, composite swap) is in test_local_scaling.gd.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_entity = autofree(Entity.new())
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(_entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	add_child(_node)
	_node.stake_level = 3
	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()
	_graph = null
	_alloc = null
	_entity = null
	_node = null


func test_fill_above_stake_level_is_an_error_and_a_no_op() -> void:
	_alloc.force_allocate(_entity, _node)
	var used_before: int = _entity.stat_board.skill_points.used
	_alloc.force_fill(_node, 4)
	assert_eq(_node.allocation_level, 1, "4 > stake_level 3: fill unchanged")
	assert_eq(_entity.stat_board.skill_points.used, used_before, "no SP touched")
	assert_push_error("force_fill")


func test_fill_on_unowned_node_is_an_error_and_a_no_op() -> void:
	_alloc.force_fill(_node, 3)
	assert_null(_node.owned_by, "still unowned")
	assert_eq(_node.allocation_level, 0, "unowned node stays empty")
	assert_push_error("force_fill")


func test_lowering_is_an_error_and_a_no_op() -> void:
	_alloc.force_allocate(_entity, _node)
	_alloc.force_fill(_node, 3)
	_alloc.force_fill(_node, 2)
	assert_eq(_node.allocation_level, 3, "lowering is not supported")
	assert_push_error("force_fill")


func test_fill_to_current_level_is_a_silent_no_op() -> void:
	_alloc.force_allocate(_entity, _node)
	_alloc.force_fill(_node, 1)
	assert_eq(_node.allocation_level, 1)
	assert_push_error_count(0)


func test_force_deallocate_after_fill_empties_fill_and_keeps_stake() -> void:
	_alloc.force_allocate(_entity, _node)
	_alloc.force_fill(_node, 3)
	assert_eq(_node.allocation_level, 3)
	var prev := _alloc.force_deallocate(_node)
	assert_eq(prev, _entity, "returns the previous owner")
	assert_null(_node.owned_by)
	assert_eq(_node.allocation_level, 0, "fill emptied")
	assert_eq(_node.stake_level, 3, "cap intact")
