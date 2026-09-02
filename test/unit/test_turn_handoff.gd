extends GutTest

## Regression suite for the "end-turn button never disables" bug.
##
## Root cause: after the player ends their turn, _tick_until_ready races the
## player and all enemies from 0 initiative. Because every entity has the same
## default speed (10) and the player is first in the "entities" group (added
## first in game_root._setup_level), the player always wins the tie — and
## gets their turn back before any enemy can act. The button disables and
## re-enables in the same synchronous call stack, so the user never sees it.
##
## After a 2nd full player turn the enemy's accumulated initiative (100, never
## deducted) beats the player by 1 tick and finally gets its turn. The button
## does disable then, but it "never comes back" — tracked in the second suite
## further down this file.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _applier: CommandApplier
var _tm: TurnManager
var _player: Entity
var _enemy: Entity
var _turn_started_for: Array[Entity] = []
var _turn_ended_for: Array[Entity] = []


func _make_entity(ent_name: String) -> Entity:
	var e := Entity.new()
	e.name = ent_name
	e.display_name = ent_name
	e.stat_board = _BOARD.duplicate(true)
	return e


func before_each() -> void:
	_turn_started_for = []
	_turn_ended_for = []

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	# Since #512 the AI ends its turn by submitting an EndTurnCommand, so this
	# fixture needs the applier — and a Graph, because a command names its actor
	# by `entity_id`, which is minted only on entry to `entities_container`
	# (#509). Nothing here allocates, so the applier needs no AllocationSystem.
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_applier = CommandApplier.new()
	_applier.graph = _graph
	_applier.turn_manager = _tm
	add_child_autofree(_applier)

	_player = autofree(_make_entity("Player"))
	_graph.entities_container.add_child(_player)

	_enemy = autofree(_make_entity("Enemy"))
	var ai := AIController.new()
	ai.turn_delay = 0.3
	ai.command_applier_override = _applier
	_enemy.add_child(ai)
	_graph.entities_container.add_child(_enemy)

	await get_tree().process_frame

	_tm.turn_started.connect(func(e: Entity) -> void: _turn_started_for.append(e))
	_tm.turn_ended.connect(func(e: Entity) -> void: _turn_ended_for.append(e))

	# Player starts ready; enemy is at 0 — the real-game configuration.
	# Both have initiative_speed 10, so after end_turn they race from 0
	# and tie at 100 simultaneously.
	_player.stat_board.initiative.restore_to_full()
	_tm.start_turn(_player)


# ---------------------------------------------------------------------------
# RED: player wins the initiative tie, enemy never gets a turn
# ---------------------------------------------------------------------------

func test_enemy_gets_turn_after_player_ends() -> void:
	# Drive the player through a full turn (single phase now — just end it).
	_tm.end_turn()

	# Expected: enemy holds the turn.
	# Actual: player and enemy both tick from 0 to 100 simultaneously;
	# player is first in the "entities" group so wins the tie and gets
	# another turn immediately — the button never disables.
	assert_eq(_tm.current_entity, _enemy,
			"enemy should have the turn after player ends their first turn")


# ---------------------------------------------------------------------------
# RED: once the enemy finally wins a tick race, the AIController coroutine
# fires correctly and the player gets their turn back.
# (Set enemy initiative_current = 50 so the enemy wins reliably — isolates
# the return-path from the tie bug above.)
# ---------------------------------------------------------------------------

func test_player_gets_turn_back_after_enemy_ai() -> void:
	_enemy.stat_board.initiative.set_current(50.0)   # head start so enemy wins the tick race

	_tm.end_turn()

	assert_eq(_tm.current_entity, _enemy, "precondition: enemy has the turn")

	await get_tree().create_timer(0.5).timeout

	assert_eq(_tm.current_entity, _player,
			"player should have the turn back after the AI timer fires")
	assert_eq(_turn_ended_for.count(_player), 1,
			"turn_ended(player) must fire exactly once — no stale AI corruption")


# ---------------------------------------------------------------------------
# #443: a turn that ends by DEATH still signals that it ended.
#
# `GameRoot._pull_from_turn_loop` used to null `current_entity` by hand, so
# `turn_ended` never fired for the acting entity's own death — an invariant
# whose only guard was `start_turn`'s `assert`, compiled out of a release
# build. `TurnManager.abandon_turn` is the explicit path.
# ---------------------------------------------------------------------------

func test_abandon_turn_ends_the_dying_actors_turn() -> void:
	assert_eq(_tm.current_entity, _player, "precondition: the player is acting")

	_tm.abandon_turn(_player)

	assert_null(_tm.current_entity, "a corpse must not keep holding the turn")
	assert_eq(_turn_ended_for.count(_player), 1,
			"turn_ended(player) must fire — a release build has no assert to catch this")


func test_abandon_turn_does_not_hand_the_clock_on() -> void:
	# Unlike `end_turn`, it deliberately does NOT `_tick_until_ready`: the
	# handoff is command-ordered (EndTurnCommand), and advancing the clock
	# locally out of a death handler reopens the group-order sync hazard that
	# command exists to close.
	_enemy.stat_board.initiative.set_current(50.0)
	var started_before := _turn_started_for.size()  # `before_each` opened the player's turn

	_tm.abandon_turn(_player)

	assert_null(_tm.current_entity, "no next turn is opened by the death path")
	assert_eq(_turn_started_for.size(), started_before,
			"abandon_turn must not start anyone's turn")


func test_abandon_turn_is_a_no_op_for_a_bystander_and_for_a_second_arrival() -> void:
	# `Entity.die()` is re-entrant from inside a forced-dealloc cascade, and
	# death fires for entities that were never acting — neither may emit a
	# second `turn_ended`.
	_tm.abandon_turn(_enemy)
	assert_eq(_tm.current_entity, _player, "a bystander's death leaves the turn alone")
	assert_true(_turn_ended_for.is_empty(), "and signals nothing")

	_tm.abandon_turn(_player)
	_tm.abandon_turn(_player)
	assert_eq(_turn_ended_for.count(_player), 1,
			"turn_ended fires exactly once no matter how often death re-enters")


func test_game_root_death_handler_routes_through_abandon_turn() -> void:
	# The wiring, not just the method: `_pull_from_turn_loop` is what a real
	# death reaches, and it must no longer write the field by hand.
	# Never `add_child`ed, exactly as `test_entity_death.gd` builds one: entering
	# the tree runs GameRoot's `@onready` block, whose `%TurnManager` lookup has
	# nothing to find outside `game_root.tscn` and would clobber this injection.
	var gr: GameRoot = autofree(GameRoot.new())
	gr.turn_manager = _tm

	gr._pull_from_turn_loop(_player)

	assert_null(_tm.current_entity, "the corpse released the turn")
	assert_eq(_turn_ended_for.count(_player), 1, "and the turn signalled its end")
	assert_false(_player.is_in_group(Entity.READY_GROUP),
			"and is out of the readiness group, as before")
