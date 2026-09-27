extends GutTest

## EntityState (#1143): the silent state an [Entity] forwards into and an
## [EntityCombat] holds — live the entity's own, shadow a combat-depth clone.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _lvl(board: EntityStatBoard) -> float:
	return board.level.value


func test_clone_is_detached_at_combat_depth() -> void:
	var s := EntityState.new()
	s.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	s.tags = {&"marked": 1}
	var core := autofree(_SKILL_NODE_SCENE.instantiate()) as SkillNode
	s.core_location = core
	var live_level := _lvl(s.stat_board)

	var c := s.clone()
	assert_not_null(c.stat_board, "the clone carries a board")
	if c.stat_board == null:
		return
	assert_ne(c.stat_board, s.stat_board, "the clone's board is its own instance")
	var m := StatModifier.new()
	m.stat_id = &"level"
	m.value = 5.0
	c.stat_board.add_modifier(m)
	assert_almost_eq(_lvl(c.stat_board), live_level + 5.0, 0.001, "the write lands on the clone")
	assert_almost_eq(_lvl(s.stat_board), live_level, 0.001, "the live board is untouched")

	assert_eq(c.tags, {&"marked": 1}, "tags are copied")
	c.tags[&"fresh"] = 1
	assert_false(s.tags.has(&"fresh"), "tags are separate")
	assert_same(c.core_location, core, "core identity is shared")


func test_entity_forwards_into_its_state() -> void:
	var e := autofree(Entity.new()) as Entity
	e.stat_board = _BOARD
	add_child(e)
	await get_tree().process_frame
	var board := e.stat_board
	assert_not_null(board, "precondition: the entity has a board")
	assert_same(e.state.stat_board, board, "Entity.stat_board is state.stat_board")
	var m := StatModifier.new()
	m.stat_id = &"level"
	m.value = 1.0
	e.grant_core_modifier(m)
	assert_same(e.stat_board, board, "same instance across a modifier add")
	assert_same(e.state.stat_board, board, "state still holds that instance")

	e.add_tag(&"marked")
	assert_eq(e.state.tags.get(&"marked", 0), 1, "tags live in the state")
	var core := autofree(_SKILL_NODE_SCENE.instantiate()) as SkillNode
	e.core_location = core
	assert_same(e.state.core_location, core, "core_location lives in the state")
	e.core_location = null
