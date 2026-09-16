extends GutTest

## #909 — TurnManager's explicit spawn-order tie-break as ONE pure ordering
## step ([method TurnManager.order_ready]), shared by the live path
## (`_tick_until_ready`) and [method TurnManager.forecast], so the HUD
## forecast strip (#910) can never drift from the real turn order.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _tm: TurnManager
var _entities: Array[Entity] = []


func _make_entity(ent_name: String, speed: float) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true)
	e.stat_board.initiative_speed.base_value = speed
	e.stat_board.initiative.current = 0.0
	return e


## Spawns entities in order (their [member Entity.entity_id] — spawn order —
## is minted on entry to `entities_container`) with the given speeds.
func _spawn_entities(speeds: Array) -> void:
	_entities = []
	for i in speeds.size():
		var e: Entity = autofree(_make_entity("E%d" % i, speeds[i]))
		_graph.entities_container.add_child(e)
		_entities.append(e)


func before_each() -> void:
	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)


# ---------------------------------------------------------------------------
# order_ready — the pure comparator

func test_equal_overshoot_orders_by_spawn_index() -> void:
	_spawn_entities([10.0, 10.0, 10.0])
	var e0 := _entities[0]
	var e1 := _entities[1]
	var e2 := _entities[2]
	# Shuffled input order; all tied on `current` (as they'd be after each
	# crosses the cap simultaneously) and no just-acted entity.
	var entries: Array[Dictionary] = [
		{"key": e2.entity_id, "current": 5.0},
		{"key": e0.entity_id, "current": 5.0},
		{"key": e1.entity_id, "current": 5.0},
	]
	var ordered := TurnManager.order_ready(entries, TurnManager.NO_LAST_KEY)
	var keys: Array[int] = []
	for entry in ordered:
		keys.append(entry["key"])
	assert_eq(keys, [e0.entity_id, e1.entity_id, e2.entity_id],
		"tied entries order by spawn index (entity_id) ascending")


func test_last_actor_goes_last_on_tie() -> void:
	_spawn_entities([10.0, 10.0, 10.0])
	var e0 := _entities[0]
	var e1 := _entities[1]
	var e2 := _entities[2]
	# e0 has the lowest entity_id — it would sort first on spawn order alone —
	# but it's the just-acted entity, so it must sort last despite the tie.
	var entries: Array[Dictionary] = [
		{"key": e0.entity_id, "current": 5.0},
		{"key": e1.entity_id, "current": 5.0},
		{"key": e2.entity_id, "current": 5.0},
	]
	var ordered := TurnManager.order_ready(entries, e0.entity_id)
	var keys: Array[int] = []
	for entry in ordered:
		keys.append(entry["key"])
	assert_eq(keys, [e1.entity_id, e2.entity_id, e0.entity_id],
		"the just-acted entity sorts last even at the lowest spawn index")


func test_higher_current_wins_regardless_of_spawn_index() -> void:
	_spawn_entities([10.0, 10.0])
	var e0 := _entities[0]
	var e1 := _entities[1]
	var entries: Array[Dictionary] = [
		{"key": e0.entity_id, "current": 3.0},
		{"key": e1.entity_id, "current": 7.0},
	]
	var ordered := TurnManager.order_ready(entries, TurnManager.NO_LAST_KEY)
	assert_eq(ordered[0]["key"], e1.entity_id, "more carried overshoot goes first")


# ---------------------------------------------------------------------------
# forecast — dry-run consistency with the live path

## Crosses [param entity]'s cap via a real [method TurnManager.tick] (not a
## raw `current = cap` write) so the pool carries its natural post-crossing
## `current`, then serves it — the same shape [method _tick_until_ready]
## produces in the real game, never the degenerate "parked exactly at cap"
## state a direct write would leave (`set_current`'s no-op guard would then
## swallow every later tick, which a real crossing never does).
func _cross_and_start(entity: Entity, near_cap_current: float) -> void:
	entity.stat_board.initiative.current = near_cap_current
	_tm.tick()
	_tm.start_turn(entity)


func test_forecast_matches_live_turns_uniform_speed() -> void:
	_spawn_entities([10.0, 10.0, 10.0])
	_cross_and_start(_entities[0], 90.0)

	var predicted := _tm.forecast(6)
	assert_eq(predicted.size(), 6, "forecast returns exactly n actors")

	var actual: Array[Entity] = []
	_tm.turn_started.connect(func(e: Entity) -> void: actual.append(e))
	for _i in 6:
		_tm.end_turn()

	assert_eq(actual.size(), 6, "drove exactly 6 more turns")
	assert_eq(predicted, actual, "forecast(6) matches the next six live turn_started actors")


func test_forecast_matches_live_turns_with_fast_entity() -> void:
	_spawn_entities([10.0, 10.0, 20.0])
	_cross_and_start(_entities[0], 90.0)

	var predicted := _tm.forecast(6)

	var actual: Array[Entity] = []
	_tm.turn_started.connect(func(e: Entity) -> void: actual.append(e))
	for _i in 6:
		_tm.end_turn()

	assert_eq(predicted, actual, "forecast(6) matches live order with a mixed-speed entity")
	assert_gt(actual.count(_entities[2]), 1,
		"the speed-20 entity (double the others) repeats within the next six turns")


func test_forecast_mutates_no_pool() -> void:
	_spawn_entities([10.0, 10.0, 10.0])
	_cross_and_start(_entities[0], 90.0)

	var before: Array[float] = []
	for e in _entities:
		before.append(e.stat_board.initiative.current)

	_tm.forecast(6)

	var after: Array[float] = []
	for e in _entities:
		after.append(e.stat_board.initiative.current)

	assert_eq(before, after, "forecast reads live pools but never writes them")
