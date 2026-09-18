extends GutTest

## #956 (C2): the node-side shot budget. `shots_fired_this_turn` is runtime
## state on SkillNode (the `regen_stacks` precedent), `shots_left()` reads the
## node-local `max_shots_per_leaf` minus it, and the FIRER's turn end resets
## exactly the nodes it fired from (`Entity._fired_nodes_this_turn`, the
## `_spiked_nodes_spent` discipline) — never a sweep, regardless of owner.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _WATCHTOWER_SCENE := preload("res://skill_node/addons/watchtower_addon.tscn")

var _graph: Graph
var _entity: Entity
var _node: SkillNode


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_entity = _make_entity()
	_node = _make_node(_entity)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()


func _make_entity() -> Entity:
	var e: Entity = autofree(Entity.new())
	e.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.add_child(e)
	return e


func _make_node(owner_entity: Entity) -> SkillNode:
	var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
	n.stake_level = 3
	n.owned_by = owner_entity
	add_child(n)
	n.allocation_level = 1
	return n


func test_fresh_level_1_leaf_has_five_shots() -> void:
	assert_eq(_node.shots_fired_this_turn, 0, "fresh node has fired nothing")
	assert_eq(_node.shots_left(), 5, "level 1: max_shots_per_leaf(5) x 1 - 0")


func test_level_2_leaf_has_ten_shots() -> void:
	_node.allocation_level = 2
	assert_eq(_node.shots_left(), 10, "level 2: MULTIPLY by stake_level__current(2)")


func test_watchtower_adds_two_shots() -> void:
	_node.add_child(_WATCHTOWER_SCENE.instantiate())
	await get_tree().process_frame
	assert_eq(_node.shots_left(), 7, "5 x 1 + watchtower ADD_BONUS(2)")


func test_mark_shot_fired_decrements_shots_left() -> void:
	_node.mark_shot_fired(3)
	assert_eq(_node.shots_fired_this_turn, 3)
	assert_eq(_node.shots_left(), 2, "5 - 3")
	_node.mark_shot_fired(9)
	assert_eq(_node.shots_left(), 0, "never negative")


func test_same_turn_dealloc_reallocate_keeps_fired_count() -> void:
	_node.mark_shot_fired(3)
	# What AllocationSystem.force_deallocate / force_allocate do to the node
	# itself: ownership flips, allocation level re-pushed.
	_node.owned_by = null
	_node.allocation_level = 0
	_node.owned_by = _entity
	_node.allocation_level = 1
	assert_eq(_node.shots_fired_this_turn, 3, "counter survives the flip")
	assert_eq(_node.shots_left(), 2, "still 2 after re-allocation")


func test_firer_turn_end_resets_fired_nodes_even_when_owned_by_another() -> void:
	_node.mark_shot_fired(3)
	_entity._fired_nodes_this_turn.append(_node)
	var other := _make_entity()
	_node.owned_by = other
	_entity._on_turn_ended(_entity)
	assert_eq(_node.shots_fired_this_turn, 0, "firer's turn end resets it")
	assert_eq(_node.shots_left(), 5)
	assert_eq(_entity._fired_nodes_this_turn.size(), 0, "fired set drained")


func test_turn_end_resets_only_the_fired_set_not_a_sweep() -> void:
	var untouched := _make_node(_entity)
	await get_tree().process_frame
	untouched.mark_shot_fired(4)
	_node.mark_shot_fired(1)
	_entity._fired_nodes_this_turn.append(_node)
	_entity._on_turn_ended(_entity)
	assert_eq(_node.shots_fired_this_turn, 0, "in the fired set: reset")
	assert_eq(untouched.shots_fired_this_turn, 4,
			"owned but not in the fired set: untouched (assert the set, not a sweep)")
	untouched.free()


func test_another_entity_turn_end_does_not_reset() -> void:
	_node.mark_shot_fired(2)
	_entity._fired_nodes_this_turn.append(_node)
	var other := _make_entity()
	_entity._on_turn_ended(other)
	assert_eq(_node.shots_fired_this_turn, 2, "not my turn end: no reset")


func test_volleys_launched_resets_at_turn_start() -> void:
	assert_eq(_entity.stat_board.volleys_per_turn.value, 5.0, "innate <- max_shots_per_leaf")
	_entity.volleys_launched_this_turn = 3
	_entity.turns_taken = 1
	_entity._on_turn_started(_entity)
	assert_eq(_entity.volleys_launched_this_turn, 0, "reset at turn start")


func test_volleys_launched_resets_even_on_first_turn() -> void:
	# The turns_taken == 1 upkeep skip must not leave a stale counter behind.
	_entity.volleys_launched_this_turn = 3
	_entity._on_turn_started(_entity)
	assert_eq(_entity.volleys_launched_this_turn, 0)
