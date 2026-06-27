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

	_player = autofree(_make_entity("Player"))
	add_child(_player)

	_enemy = autofree(_make_entity("Enemy"))
	var ai := AIController.new()
	ai.turn_delay = 0.3
	_enemy.add_child(ai)
	add_child(_enemy)

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
