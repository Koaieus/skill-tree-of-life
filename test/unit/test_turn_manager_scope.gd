extends GutTest

## One tree, two worlds (the editor's sandbox host mounts every live tab at
## once): a TurnManager scoped by [member TurnManager.entity_root] serves only
## its own world's entities, and an entity bound through
## [member Entity.turn_manager_override] hears only that manager.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _foreign_tm: TurnManager
var _tm: TurnManager
var _home: Graph
var _away: Graph


func _make_entity(ent_name: String, tm: TurnManager = null) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.stat_board = _BOARD.duplicate(true)
	e.stat_board.initiative.current = 0.0
	e.turn_manager_override = tm
	return e


func before_each() -> void:
	# Added first, so it is the group's first member — what an unwired entity
	# would bind to.
	_foreign_tm = TurnManager.new()
	add_child_autofree(_foreign_tm)
	_tm = TurnManager.new()
	add_child_autofree(_tm)
	_home = _GRAPH_SCENE.instantiate()
	add_child_autofree(_home)
	_away = _GRAPH_SCENE.instantiate()
	add_child_autofree(_away)
	_tm.entity_root = _home


func test_a_scoped_tick_replenishes_only_its_own_world() -> void:
	var mine := _make_entity("Mine", _tm)
	_home.entities_container.add_child(mine)
	var theirs := _make_entity("Theirs")
	_away.entities_container.add_child(theirs)
	_tm.tick()
	assert_gt(mine.stat_board.initiative.current, 0.0, "the scoped world's clock advances")
	assert_eq(theirs.stat_board.initiative.current, 0.0, "a foreign world's entity is never ticked")


func test_end_turn_hands_the_turn_back_to_the_lone_scoped_entity() -> void:
	var mine := _make_entity("Mine", _tm)
	_home.entities_container.add_child(mine)
	# Equally fast and spawned first: unscoped, it would be served instead.
	var theirs := _make_entity("Theirs")
	_away.entities_container.add_child(theirs)
	_tm.start_turn(mine)
	_tm.end_turn()
	assert_eq(_tm.current_entity, mine, "with one entity in scope, end_turn rolls into its next turn")


func test_an_override_binds_the_entity_to_that_manager() -> void:
	var mine := _make_entity("Mine", _tm)
	_home.entities_container.add_child(mine)
	var before := mine.turns_taken
	_tm.start_turn(mine)
	assert_eq(mine.turns_taken, before + 1, "the wired manager's turn reaches the entity")
