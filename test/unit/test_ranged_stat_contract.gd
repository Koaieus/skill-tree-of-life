extends GutTest

## Pre-step for #955 (C1) / #956 (C2): the four shared ranged StatDefs and the
## two intrinsic scalings they need to already work before either lands.
## Not the full C1/C2 acceptance (Quiver, shot counters, commands) — just the
## stat contract: the defs exist, the innate volleys_per_turn formula reads
## through, and arrows_per_reload / max_shots_per_leaf scale by allocation
## level the same way addon_slots does (MULTIPLY-by-stake_level).

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _WATCHTOWER_SCENE := preload("res://skill_node/addons/watchtower_addon.tscn")

var _node: SkillNode


func before_each() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.add_child(entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_node.stake_level = 3
	_node.owned_by = entity
	add_child(_node)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(_node):
		_node.free()


func test_volleys_per_turn_reads_max_shots_per_leaf_by_default() -> void:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	board.apply_intrinsics()
	assert_eq(board.volleys_per_turn.value, 5.0,
			"base 0 + ADD_BONUS(LinearFormula(max_shots_per_leaf)) == 5")


func test_level_1_leaf_reads_base_max_shots_per_leaf() -> void:
	_node.allocation_level = 1
	assert_eq(int(_node.get_local_value(&"max_shots_per_leaf")), 5,
			"MULTIPLY by stake_level__current(1) leaves the base(5) unchanged")


func test_level_2_leaf_doubles_max_shots_per_leaf() -> void:
	_node.allocation_level = 2
	assert_eq(int(_node.get_local_value(&"max_shots_per_leaf")), 10,
			"MULTIPLY by stake_level__current(2)")


func test_level_2_leaf_doubles_arrows_per_reload() -> void:
	_node.allocation_level = 2
	assert_eq(int(_node.get_local_value(&"arrows_per_reload")), 4,
			"MULTIPLY by stake_level__current(2)")


func test_watchtower_adds_flat_bonus_on_top() -> void:
	_node.allocation_level = 1
	_node.add_child(_WATCHTOWER_SCENE.instantiate())
	await get_tree().process_frame
	assert_eq(int(_node.get_local_value(&"max_shots_per_leaf")), 7,
			"base(5) x stake(1) + watchtower ADD_BONUS(2)")
	assert_eq(int(_node.get_local_value(&"arrows_per_reload")), 3,
			"base(2) x stake(1) + watchtower ADD_BONUS(1)")
