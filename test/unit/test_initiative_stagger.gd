extends GutTest

## #911 — opening initiative is staggered across spawn order instead of every
## entity opening at 0 and the tie-break deciding the whole race every cycle.
##
## [method GameRoot.apply_initiative_stagger] is the pure half (spawn-ordered
## carriers in, `current` rewritten via [method PoolStat.set_current] out) —
## tested here with hand-built entities, no [Graph]/[GameRoot] scene needed.
## [method GameRoot._stagger_initiative] (the instance half that reads
## `graph.entities_container` and [autoload GameSession]'s
## [member RunConfig.stagger_initiative] bool) is exercised separately below.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _tm: TurnManager


func _make_entity(ent_name: String) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true)
	return e


func _spawn_n(n: int) -> Array[Entity]:
	var out: Array[Entity] = []
	for i in n:
		var e := _make_entity("E%d" % i)
		_graph.entities_container.add_child(e)
		out.append(e)
	return out


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)
	_tm = autofree(TurnManager.new())
	add_child(_tm)


func after_each() -> void:
	GameSession.end()


## Ranks 1..n-1 never cross the cap, so they land exactly on the formula's
## `floor(cap * (n-i)/n)`. Rank 0 (i=0, value == cap) is a special case —
## see the next test.
func test_non_first_ranks_land_exactly_on_the_formula() -> void:
	var carriers := _spawn_n(4)
	await wait_physics_frames(1)

	GameRoot.apply_initiative_stagger(carriers)

	assert_eq(carriers[1].stat_board.initiative.current, 75.0)
	assert_eq(carriers[2].stat_board.initiative.current, 50.0)
	assert_eq(carriers[3].stat_board.initiative.current, 25.0)


## Rank 0's formula value IS the cap — and [CyclicPoolStatDef] treats landing
## on the cap as a crossing: `on_pool_filled` immediately carries the excess
## (0, landing exactly on it) back to `current`, the same mechanism
## `GameRoot._open_first_turn`'s offline path already leans on via
## `restore_to_full()` ("fill the player's clock so they act first"). So
## "cap" is the formula's input, not a promise about the stored `current`
## afterward — readiness is [Entity.READY_GROUP] membership, not the value
## (see `Entity._on_initiative_ready`'s own comment to that effect). Rank 0
## ends up ready to act at once, `current` reset to the carry (0 here), same
## as every other entity that ever crosses the cap.
func test_first_rank_is_ready_at_once_rather_than_parked_at_the_cap() -> void:
	var carriers := _spawn_n(4)
	await wait_physics_frames(1)

	GameRoot.apply_initiative_stagger(carriers)

	assert_true(carriers[0].is_in_group(Entity.READY_GROUP))
	assert_eq(carriers[0].stat_board.initiative.current, 0.0)


func test_bool_off_leaves_every_entity_at_zero() -> void:
	var carriers := _spawn_n(3)
	await wait_physics_frames(1)
	var root := GameRoot.new()
	root.graph = _graph
	GameSession.config = RunConfig.new()
	GameSession.config.stagger_initiative = false

	root._stagger_initiative()

	for e in carriers:
		assert_eq(e.stat_board.initiative.current, 0.0)
	assert_false(carriers[0].is_in_group(Entity.READY_GROUP))


func test_bool_on_by_default_stages_the_first_rank_ready() -> void:
	var carriers := _spawn_n(3)
	await wait_physics_frames(1)
	var root := GameRoot.new()
	root.graph = _graph
	GameSession.config = RunConfig.new()
	assert_true(GameSession.config.stagger_initiative, "default is on")

	root._stagger_initiative()

	assert_true(carriers[0].is_in_group(Entity.READY_GROUP))
	assert_eq(carriers[1].stat_board.initiative.current, 66.0)  # floor(100*2/3)


## The mirror trap (#911, Sage review): index 0 must be the entity the opening
## [StartTurnCommand] will name — the AUTHORITY's (host's) seat — not
## whichever entity this machine happens to have spawned first. Here the
## host's seat (`peer_id == NetworkTransport.HOST_PEER_ID`) is spawned SECOND;
## the stagger must still rank it first.
func test_host_seat_ranks_first_even_when_spawned_second() -> void:
	var carriers := _spawn_n(2)  # carriers[0] spawned first, carriers[1] second
	carriers[0].participant_id = 10
	carriers[1].participant_id = 20
	await wait_physics_frames(1)
	var root := GameRoot.new()
	root.graph = _graph
	GameSession.config = RunConfig.new()
	GameSession.network = NetworkConfig.new()
	GameSession.network.role = NetworkTransport.Role.HOST
	GameSession.roster = ParticipantRoster.new()
	var p_first := Participant.new()
	p_first.id = 10
	p_first.peer_id = 5  # a joined client, not the host
	GameSession.roster.add(p_first)
	var p_second := Participant.new()
	p_second.id = 20
	p_second.peer_id = NetworkTransport.HOST_PEER_ID
	GameSession.roster.add(p_second)

	root._stagger_initiative()

	assert_true(carriers[1].is_in_group(Entity.READY_GROUP),
			"the host's seat (spawned 2nd) should rank 0, not the entity spawned 1st")
	assert_false(carriers[0].is_in_group(Entity.READY_GROUP))
	assert_eq(carriers[0].stat_board.initiative.current, 50.0)  # rank 1 of 2


## Blockers (no `initiative` pool — the bare [Entity] default has none until
## a board with one is assigned) are not counted in `n` and are untouched.
func test_blockers_are_excluded_and_untouched() -> void:
	var carriers := _spawn_n(2)
	var blocker := Entity.new()
	blocker.name = "Blocker"
	_graph.entities_container.add_child(blocker)
	await wait_physics_frames(1)
	var root := GameRoot.new()
	root.graph = _graph
	GameSession.config = RunConfig.new()

	root._stagger_initiative()

	# n stayed 2 (the two carriers), not 3 — rank 1 of {2,1} still reads cap/2.
	assert_eq(carriers[1].stat_board.initiative.current, 50.0)
	assert_null(blocker.stat_board)


## Acceptance spec #1's second half: driving `end_turn()` for two full cycles
## across four staggered entities yields eight distinct crossing ticks — no
## two entities cross the cap on the same tick, unlike today's "every entity
## opens at 0, all cross together, tie-break decides everything" baseline.
func test_two_cycles_cross_at_eight_distinct_ticks() -> void:
	var carriers := _spawn_n(4)
	await wait_physics_frames(1)
	GameRoot.apply_initiative_stagger(carriers)

	# A local `int` is captured BY VALUE in a lambda (GUT/GDScript closures over
	# a bare local do not alias it) — a single-element array is the mutable box.
	var tick_count := [0]
	_tm.ticked.connect(func() -> void: tick_count[0] += 1)
	var acted: Array[Entity] = []
	_tm.turn_started.connect(func(e: Entity) -> void: acted.append(e))

	# Rank 0 opens the run already ready — mirrors [StartTurnCommand] handing
	# the opening turn to it directly, no tick spent.
	_tm.start_turn(carriers[0])
	var crossing_ticks: Array[int] = [tick_count[0]]

	for _turn in range(7):  # 2 full cycles of 4 entities, minus the opening turn
		_tm.end_turn()
		crossing_ticks.append(tick_count[0])

	assert_eq(acted.size(), 8)
	var distinct := {}
	for t in crossing_ticks:
		distinct[t] = true
	assert_eq(distinct.size(), 8,
			"expected 8 distinct crossing ticks, got %s" % [crossing_ticks])
