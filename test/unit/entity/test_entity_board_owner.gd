extends GutTest

## `Entity.stat_board` has one owner (#1031): outside the editor the setter
## stores a private `duplicate(true)` from the moment of assignment, and once
## `initialize()` has brought the entity up nothing replaces it (`push_error`,
## write ignored). The #983 property — a reader that grabbed the board before
## `add_child` still holds the live one after — follows from the two.
##
## The `Engine.is_editor_hint()` branch (store the shared ext_resource as
## given, duplicate inside `initialize()`) cannot be toggled from a test; it
## is covered by `mise run refresh` plus the allocation / loot sandbox tabs
## bringing up their authored entities.

const _BOARD := preload("res://entity/default_entity_board.tres")


func test_assignment_stores_a_private_copy() -> void:
	var b := _BOARD.duplicate(true) as EntityStatBoard
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = b
	assert_ne(entity.stat_board, b, "the entity owns a copy, never the caller's object")
	assert_is(entity.stat_board, EntityStatBoard)
	assert_not_null(entity.stat_board.health, "the copy carries B's stats")
	assert_eq(entity.stat_board.get_stat(&"node_health").base_value,
			b.get_stat(&"node_health").base_value, "…with B's values")


func test_board_identity_survives_bring_up() -> void:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	var before: EntityStatBoard = entity.stat_board
	add_child(entity)
	assert_true(entity._initialized, "sanity: _ready ran initialize()")
	assert_same(entity.stat_board, before,
			"the object read before add_child is the live board after bring-up")


func test_assignment_after_bring_up_is_refused() -> void:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(entity)
	var live: EntityStatBoard = entity.stat_board
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	assert_same(entity.stat_board, live, "a post-seal write is ignored")
	assert_push_error_count(1)
