extends GutTest

## #1257 — [TurnManager]'s initiative ROUND: it opens with a roster of every
## living initiative carrier, and completes when the last roster member still
## waiting ENDS its turn; the next opens at once with a fresh roster. Only turn
## order matters, never tick counts.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _tm: TurnManager
var _entities: Array[Entity] = []

## Enders since the last round closed; one snapshot per completed round.
var _since: Array[Entity] = []
var _rounds_log: Array = []


func _make_entity(ent_name: String, speed: float) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true)
	e.stat_board.initiative_speed.base_value = speed
	e.stat_board.initiative.current = 0.0
	return e


func _spawn(ent_name: String, speed: float) -> Entity:
	var e: Entity = autofree(_make_entity(ent_name, speed))
	_graph.entities_container.add_child(e)
	_entities.append(e)
	return e


func _build(speeds: Array) -> void:
	_entities = []
	_since = []
	_rounds_log = []
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_tm = autofree(TurnManager.new())
	_tm.entity_root = _graph
	add_child(_tm)
	for i in speeds.size():
		_spawn("E%d" % i, speeds[i])
	# `round_completed` fires just before the closing turn's `turn_ended`, so
	# the snapshot is taken once that ender has been appended.
	var closing := [false]
	_tm.round_completed.connect(func(_r: int) -> void: closing[0] = true)
	_tm.turn_ended.connect(func(e: Entity) -> void:
		_since.append(e)
		if closing[0]:
			closing[0] = false
			_rounds_log.append(_since.duplicate())
			_since.clear())


## What GameRoot's turn-loop pull does for a corpse: a bare fixture has nothing
## else taking it out of [constant Entity.GROUP].
func _kill(e: Entity) -> void:
	e.die()
	e.remove_from_group(Entity.GROUP)


func test_a_round_completes_only_once_every_member_has_ended() -> void:
	_build([10.0, 10.0, 30.0])
	_tm.start_turn(_entities[0])
	for _i in 14:
		_tm.end_turn()
	assert_gte(_rounds_log.size(), 2, "sanity: several rounds were played")
	assert_eq(_tm.rounds_completed, _rounds_log.size())
	for enders in _rounds_log:
		for e in _entities:
			assert_true((enders as Array).has(e),
					"%s ended its turn before the round closed" % e.name)
	assert_gte((_rounds_log[0] as Array).count(_entities[2]), 2,
			"the fast entity acted twice inside round 1 without closing it early")


func test_an_entity_added_mid_round_does_not_delay_it() -> void:
	_build([10.0, 10.0])
	_tm.start_turn(_entities[0])
	var late := _spawn("Late", 10.0)
	late.stat_board.initiative.current = 95.0
	assert_false(_tm.round_waiting().has(late), "a late joiner waits for the next roster")
	for _i in 6:
		if _tm.rounds_completed > 0:
			break
		_tm.end_turn()
	assert_eq(_tm.rounds_completed, 1)
	var enders: Array = _rounds_log[0]
	assert_true(enders.has(_entities[0]) and enders.has(_entities[1]))
	assert_true(_tm.round_waiting().has(late), "the next roster includes the joiner")


func test_a_member_dying_off_turn_is_dropped() -> void:
	_build([10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	_kill(_entities[2])
	assert_false(_tm.round_waiting().has(_entities[2]), "a corpse leaves the roster")
	_tm.end_turn()
	_tm.end_turn()
	assert_eq(_tm.rounds_completed, 1, "the round closes on the living members alone")


func test_a_member_abandoning_its_turn_is_dropped() -> void:
	_build([10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	_tm.end_turn()
	var actor := _tm.current_entity
	_kill(actor)
	_tm.abandon_turn(actor)
	assert_false(_tm.round_waiting().has(actor))
	assert_eq(_tm.round_waiting().size(), 1, "one living member still waits")


func _play(speeds: Array, turns: int) -> Dictionary:
	_build(speeds)
	var actors: Array[String] = []
	_tm.turn_started.connect(func(e: Entity) -> void: actors.append(e.name))
	_tm.start_turn(_entities[0])
	for _i in turns:
		_tm.end_turn()
	return {"rounds": _tm.rounds_completed, "actors": actors}


func test_scaling_every_gain_by_ten_leaves_the_round_count_unchanged() -> void:
	var slow := _play([1.0, 1.0, 2.0], 12)
	var fast := _play([10.0, 10.0, 20.0], 12)
	assert_eq(fast["actors"], slow["actors"], "sanity: the same sequence of turns")
	assert_gt(slow["rounds"], 0, "sanity: rounds were counted at all")
	assert_eq(fast["rounds"], slow["rounds"], "rounds depend on order, never ticks")


func test_adopt_turn_lands_on_the_authoritys_round_state() -> void:
	_build([10.0, 10.0, 10.0])
	_tm.start_turn(_entities[0])
	for _i in 4:
		_tm.end_turn()
	var authority := _tm
	assert_gt(authority.rounds_completed, 0, "sanity")

	var mirror: TurnManager = autofree(TurnManager.new())
	mirror.entity_root = _graph
	add_child(mirror)
	watch_signals(mirror)
	mirror.adopt_turn(authority.current_entity, authority.turns_taken,
			authority.rounds_completed, true, authority.round_waiting())

	assert_eq(mirror.rounds_completed, authority.rounds_completed)
	assert_eq(mirror.round_waiting(), authority.round_waiting())
	assert_signal_not_emitted(mirror, "round_completed", "a repair has no presentation")
