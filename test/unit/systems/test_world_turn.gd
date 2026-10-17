extends GutTest

## ADR 0055 — [TurnManager]'s WORLD TURN: one ends every N played turn ends,
## N = the living initiative carriers. Counts turns, never ticks; only a played
## turn end ([method TurnManager.end_turn]) counts.

const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _tm: TurnManager
var _entities: Array[Entity] = []
## One entry per `world_turn_ended`.
var _world_turns: Array = []
var _enders: Array[Entity] = []


func _spawn(ent_name: String, speed: float) -> Entity:
	var e: Entity = autofree(Entity.new())
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true)
	e.stat_board.initiative_speed.base_value = speed
	e.stat_board.initiative.current = 0.0
	_graph.entities_container.add_child(e)
	_entities.append(e)
	return e


func _build(speeds: Array) -> void:
	_entities = []
	_world_turns = []
	_enders = []
	_graph = TestWorld.create(self).graph
	_tm = autofree(TurnManager.new())
	_tm.entity_root = _graph
	add_child(_tm)
	for i in speeds.size():
		_spawn("E%d" % i, speeds[i])
	_tm.world_turn_ended.connect(func() -> void: _world_turns.append(true))
	_tm.turn_ended.connect(func(e: Entity) -> void: _enders.append(e))


## What GameRoot's turn-loop pull does for a corpse.
func _kill(e: Entity) -> void:
	e.die()
	e.remove_from_group(Entity.GROUP)


func _a_bystander() -> Entity:
	for e in _entities:
		if e != _tm.current_entity and not e.is_dead:
			return e
	return null


func test_equal_speeds_end_one_world_turn_per_three_turn_ends() -> void:
	_build([10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	_tm.end_turn()
	_tm.end_turn()
	assert_eq(_world_turns.size(), 0, "two of three played turn ends: still open")
	assert_eq(_tm.world_turn_progress, 2)
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "the third closes the world turn")
	assert_eq(_tm.world_turn_progress, 0, "and resets the counter")
	for _i in 6:
		_tm.end_turn()
	assert_eq(_world_turns.size(), 3, "exactly one per three turn ends")


func test_mixed_speeds_count_turn_ends_not_who_played_them() -> void:
	_build([10.0, 30.0])
	_tm.start_turn(_entities[1])
	_tm.end_turn()
	assert_eq(_tm.current_entity, _entities[1], "sanity: the fast one plays again")
	_tm.end_turn()
	assert_eq(_enders, [_entities[1], _entities[1]] as Array[Entity],
			"sanity: both played turn ends were the fast one's")
	assert_eq(_world_turns.size(), 1, "N = 2 played turn ends close the world turn")
	assert_eq(_tm.rounds_completed, 0,
			"while the round still waits on the slow one — a world turn is not a round")


func test_a_death_mid_cycle_shrinks_n() -> void:
	_build([10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	_tm.end_turn()
	assert_eq(_tm.world_turn_progress, 1, "sanity: 1 of 3")
	_kill(_a_bystander())
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "2 of the 2 living closes the world turn")


func test_progress_past_a_shrunk_n_closes_at_the_next_turn_end() -> void:
	_build([10.0, 10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	for _i in 3:
		_tm.end_turn()
	assert_eq(_tm.world_turn_progress, 3, "sanity: 3 of 4")
	_kill(_a_bystander())
	_kill(_a_bystander())
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "4 >= 2: a progress beyond N still closes it")
	assert_eq(_tm.world_turn_progress, 0)


func test_abandon_turn_never_counts() -> void:
	_build([10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	_tm.end_turn()
	var actor := _tm.current_entity
	_kill(actor)
	_tm.abandon_turn(actor)
	assert_eq(_enders.size(), 2, "sanity: the abandon emitted turn_ended")
	assert_eq(_tm.world_turn_progress, 1, "a death is not a played turn end")
	assert_eq(_world_turns.size(), 0)


func test_adopt_turn_never_counts() -> void:
	_build([10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	_tm.end_turn()
	_tm.adopt_turn(_a_bystander(), _tm.turns_taken)
	_tm.adopt_turn(_a_bystander(), _tm.turns_taken)
	assert_eq(_tm.world_turn_progress, 1, "a resync without round state leaves it untouched")
	assert_eq(_world_turns.size(), 0)


func test_adopt_turn_sets_the_world_progress() -> void:
	_build([10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	_tm.adopt_turn(_tm.current_entity, _tm.turns_taken, 0, true,
			_tm.round_waiting(), 2)
	assert_eq(_tm.world_turn_progress, 2, "adopted outright")
	assert_eq(_world_turns.size(), 0, "a repair never emits")
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "and the adopted progress is the one counted on")
