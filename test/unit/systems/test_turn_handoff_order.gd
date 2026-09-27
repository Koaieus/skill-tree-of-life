extends GutTest

## The turn handoff is a call sequence, not a connect-order convention:
## [method TurnManager.start_turn] runs [method Entity.begin_turn] (upkeep, then
## [signal Entity.turn_began] → the controller's [method EntityController.take_turn])
## BEFORE any [signal TurnManager.turn_started] listener hears it, and
## [method TurnManager.end_turn] runs [method Entity.finish_turn] before
## [signal TurnManager.turn_ended]. [method TurnManager.adopt_turn] runs neither.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")


## Records what the entity looked like when its turn reached the controller.
class _ProbeController:
	extends EntityController
	var seen_turns_taken: Array[int] = []

	func take_turn() -> void:
		seen_turns_taken.append(entity.turns_taken)


var _tm: TurnManager
var _graph: Graph


func before_each() -> void:
	_tm = TurnManager.new()
	add_child_autofree(_tm)
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_tm.entity_root = _graph


func _make_entity(ent_name: String) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.stat_board = _BOARD.duplicate(true)
	e.stat_board.initiative.current = 0.0
	return e


func test_turn_started_listeners_see_the_upkeep_already_applied() -> void:
	# Connected BEFORE the entity exists, so no connect order can rescue it.
	var seen: Array[int] = []
	_tm.turn_started.connect(func(e: Entity) -> void: seen.append(e.turns_taken))
	var e := _make_entity("E")
	_graph.entities_container.add_child(e)
	var before := e.turns_taken
	_tm.start_turn(e)
	assert_eq(seen, [before + 1] as Array[int], "turn_started fires after begin_turn has counted the turn")
	assert_true(e.is_taking_turn, "begin_turn marks the entity as taking its turn")


func test_a_controller_attached_before_its_entity_enters_the_tree_acts_after_upkeep() -> void:
	var e := _make_entity("E")
	var ctrl := _ProbeController.new()
	e.add_child(ctrl)
	_graph.entities_container.add_child(e)
	var before := e.turns_taken
	_tm.start_turn(e)
	assert_eq(ctrl.seen_turns_taken, [before + 1] as Array[int],
			"take_turn runs exactly once, after the upkeep")


func test_adopt_turn_runs_no_upkeep_and_no_take_turn_but_marks_the_turn() -> void:
	var e := _make_entity("E")
	var ctrl := _ProbeController.new()
	e.add_child(ctrl)
	_graph.entities_container.add_child(e)
	var before := e.turns_taken
	_tm.adopt_turn(e, 7)
	assert_eq(e.turns_taken, before, "an adopted cursor is not a turn served")
	assert_eq(ctrl.seen_turns_taken.size(), 0, "a mirror's controller never acts on an adopted turn")
	assert_true(e.is_taking_turn, "the adopted entity is not lying about whose turn it is")


func test_a_controller_kicked_by_hand_mid_turn_may_continue() -> void:
	var e := _make_entity("E")
	_graph.entities_container.add_child(e)
	_tm.start_turn(e)
	# The seat-handover case: the controller never heard turn_began.
	var ai := AIController.new()
	ai.turn_delay = 0.0
	e.add_child(ai)
	assert_true(ai._continue(), "a handed-over turn reads as live to the new controller")


func test_end_turn_finishes_the_entity_before_turn_ended_listeners_hear() -> void:
	var finished_first: Array[bool] = []
	var e := _make_entity("E")
	var heard_finish := [false]
	e.turn_finished.connect(func() -> void: heard_finish[0] = true)
	_tm.turn_ended.connect(func(_x: Entity) -> void: finished_first.append(heard_finish[0] and not e.is_taking_turn))
	_graph.entities_container.add_child(e)
	# A second in-scope entity so end_turn's tick has somewhere to hand on to.
	_graph.entities_container.add_child(_make_entity("Other"))
	_tm.start_turn(e)
	_tm.end_turn()
	assert_eq(finished_first, [true] as Array[bool], "finish_turn ran before turn_ended was heard")
