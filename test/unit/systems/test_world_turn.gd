extends GutTest

## ADR 0055 — [TurnManager]'s WORLD TURN: one ends every N played turn ends,
## N = the living initiative carriers. Counts turns, never ticks; only a played
## turn end ([method TurnManager.end_turn]) counts.

const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _tw: TestWorld
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
	_tw = TestWorld.create(self)
	_graph = _tw.graph
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


# ── The rate rule (#1795): CEIL_SQRT is the option; the cases above pin the default.


func test_world_turn_period_sweeps_both_rules() -> void:
	var bad: Array = []
	for n in range(0, 101):
		var lin := TurnManager.world_turn_period(n, TurnManager.WorldClock.PER_CARRIER)
		if lin != maxi(1, n):
			bad.append("PER_CARRIER n=%d -> %d" % [n, lin])
		var s := TurnManager.world_turn_period(n, TurnManager.WorldClock.CEIL_SQRT)
		if s < 1 or s * s < n or (n >= 1 and (s - 1) * (s - 1) >= n):
			bad.append("CEIL_SQRT n=%d -> %d" % [n, s])
	assert_eq(bad, [], "max(1, n); the least s >= 1 with s*s >= n")


func test_ceil_sqrt_closes_a_world_turn_every_two_ends_for_four_carriers() -> void:
	_build([10.0, 10.0, 10.0, 10.0])
	_tm.world_clock = TurnManager.WorldClock.CEIL_SQRT
	_tm.start_turn(_entities[0])
	_tm.end_turn()
	assert_eq(_world_turns.size(), 0, "1 of 2")
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "2 of 2: ⌈√4⌉ = 2")
	_tm.end_turn()
	_tm.end_turn()
	assert_eq(_world_turns.size(), 2)


func test_ceil_sqrt_a_death_that_shrinks_the_period_below_progress_closes_next_end() -> void:
	var speeds := []
	speeds.resize(17)
	speeds.fill(10.0)
	_build(speeds)
	_tm.world_clock = TurnManager.WorldClock.CEIL_SQRT
	_tm.start_turn(_entities[0])
	for _i in 4:
		_tm.end_turn()
	assert_eq(_world_turns.size(), 0, "sanity: 4 of ⌈√17⌉ = 5")
	for _i in 8:
		_kill(_a_bystander())
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "9 living: period 3, below the progress 4 — closes")
	assert_eq(_tm.world_turn_progress, 0)


func test_a_world_turn_runs_the_terrain_pass_with_its_steps() -> void:
	CombatWorld.reset_live()
	_build([10.0, 10.0])
	var x := _tw.add_node(&"X")
	var y := _tw.add_node(&"Y")
	var z := _tw.add_node(&"Z")
	_tw.link(x, y)
	_tw.link(y, z)
	await get_tree().process_frame
	var fire := ElementRoster.shared().by_id(&"fire")
	_tm.terrain_steps_per_world_turn = 2
	x.get_combat().add_terrain(fire, 30)
	_tm.start_turn(_entities[0])
	_tm.end_turn()
	_tm.end_turn()
	assert_eq(_world_turns.size(), 1, "sanity: one world turn")
	var got := [x.state.terrain_t, y.state.terrain_t, z.state.terrain_t]
	for n: SkillNode in [x, y, z]:
		n.get_combat().add_terrain(fire, -n.state.terrain_t)
	x.get_combat().add_terrain(fire, 30)
	CombatWorld.live().flow_temperature(2)
	assert_ne(got, [30, 0, 0], "the world turn moved the terrain")
	assert_eq(got, [x.state.terrain_t, y.state.terrain_t, z.state.terrain_t],
			"exactly as the pass with two steps does")
	CombatWorld.reset_live()
