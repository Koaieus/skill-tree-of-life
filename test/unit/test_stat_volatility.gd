extends GutTest

## A stat is volatile on a read iff a modifier that read folds has
## valence(board) == VOLATILE — entity readout scans the entity board,
## node-local scans node board + owner's entity board.

const _PACIFIST := preload("res://entity/core/pacifist_core.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


func _mod(id: StringName, op: StatModifier.Operation, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = id
	m.operation = op
	m.value = value
	return m


# --- 1. bind / unbind a sign flip --------------------------------------------

func test_sign_flip_multiply_toggles_volatility() -> void:
	var board := TestBoards.flat_entity_board()
	assert_false(board.is_stat_volatile(&"min_damage_taken"))
	var flip := _mod(&"min_damage_taken", StatModifier.Operation.MULTIPLY, -1.0)
	board.add_modifier(flip)
	assert_true(board.is_stat_volatile(&"min_damage_taken"))
	board.remove_modifier(flip)
	assert_false(board.is_stat_volatile(&"min_damage_taken"))


func test_unknown_id_is_not_volatile_and_mints_nothing() -> void:
	var board := TestBoards.flat_entity_board()
	assert_false(board.is_stat_volatile(&"not_a_real_stat"))
	assert_null(board.get_stat(&"not_a_real_stat"))


# --- 2. SET ------------------------------------------------------------------

func test_set_modifier_makes_stat_volatile() -> void:
	var board := TestBoards.flat_entity_board()
	board.add_modifier(_mod(&"armor", StatModifier.Operation.SET, 0.0))
	assert_true(board.is_stat_volatile(&"armor"))


func test_pacifist_core_set_stats_read_volatile() -> void:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = TestBoards.flat_entity_board()
	entity.core_class = _PACIFIST
	add_child_autofree(entity)
	await get_tree().process_frame
	var board: StatBoard = entity.stat_board
	for m in _PACIFIST.modifiers:
		if m.operation == StatModifier.Operation.SET:
			assert_true(board.is_stat_volatile(m.stat_id), "%s should be volatile" % m.stat_id)


# --- 3. boon / bane alone -----------------------------------------------------

func test_boon_and_bane_alone_are_not_volatile() -> void:
	var board := TestBoards.flat_entity_board()
	board.add_modifier(_mod(&"armor", StatModifier.Operation.MULTIPLY, 2.0))
	board.add_modifier(_mod(&"dexterity", StatModifier.Operation.ADD_BASE, -1.0))
	assert_false(board.is_stat_volatile(&"armor"))
	assert_false(board.is_stat_volatile(&"dexterity"))


# --- 4. node-local: either board ---------------------------------------------

func _owned_node() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = TestBoards.flat_entity_board()
	graph.add_child(entity)
	var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(node)
	await get_tree().process_frame
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	alloc.force_allocate(entity, node)
	return {"entity": entity, "node": node}


func test_entity_board_flip_is_node_local_volatile() -> void:
	var s: Dictionary = await _owned_node()
	var node: SkillNode = s.node
	assert_false(node.is_local_volatile(&"min_damage_taken"))
	s.entity.stat_board.add_modifier(_mod(&"min_damage_taken", StatModifier.Operation.MULTIPLY, -1.0))
	assert_true(node.is_local_volatile(&"min_damage_taken"))


func test_node_board_flip_alone_is_node_local_volatile() -> void:
	var s: Dictionary = await _owned_node()
	var node: SkillNode = s.node
	node.add_local_modifier(_mod(&"min_damage_taken", StatModifier.Operation.MULTIPLY, -1.0))
	assert_false(s.entity.stat_board.is_stat_volatile(&"min_damage_taken"))
	assert_true(node.is_local_volatile(&"min_damage_taken"))


# --- 5. formula MULTIPLY judged on its effective value -----------------------

func test_formula_multiply_volatile_when_effective_value_non_positive() -> void:
	var board := TestBoards.flat_entity_board()
	board.strength.base_value = 0.0
	var lin := LinearFormula.new()
	lin.source_stat_id = &"strength"
	var m := _mod(&"armor", StatModifier.Operation.MULTIPLY, 2.0)
	m.formula = lin
	board.add_modifier(m)
	assert_true(board.is_stat_volatile(&"armor"), "coefficient 2 x strength 0 = x0")
	board.strength.base_value = 3.0
	assert_false(board.is_stat_volatile(&"armor"), "x6 is a plain boon")
