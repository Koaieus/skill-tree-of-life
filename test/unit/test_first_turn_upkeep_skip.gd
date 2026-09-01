extends GutTest

## An entity's FIRST turn runs no start-of-turn upkeep at all — you open in the
## state you spawned in, not one free tick of income richer.
##
## Every pool on `default_entity_board.tres` is authored at its cap, so the
## skipped REFILLs and the health/mana ADDs were already no-ops on turn 1; what
## the gate actually removes is a turn of `xp_per_turn`, which used to level a
## fresh entity before it had made a single move. These tests pin both halves:
## turn 1 changes nothing, turn 2 is a completely ordinary upkeep.

const _BOARD := preload("res://entity/default_entity_board.tres")

var _entity: Entity


func before_each() -> void:
	_entity = Entity.new()
	autofree(_entity)
	_entity.display_name = "Freshling"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(_entity)
	await get_tree().process_frame


func test_first_turn_grants_no_xp() -> void:
	assert_gt(float(_entity.stat_board.xp_per_turn.get_value()), 0.0,
			"precondition: WIS baseline gives this entity real xp income")
	var xp_before: float = _entity.stat_board.xp.current
	_entity._on_turn_started(_entity)
	assert_eq(_entity.stat_board.xp.current, xp_before,
			"an entity's first turn must not tick xp income")


func test_first_turn_does_not_level_a_fresh_entity() -> void:
	var level_before: int = _entity.level
	_entity._on_turn_started(_entity)
	assert_eq(_entity.level, level_before,
			"xp_per_turn used to fill the level-1 xp cap outright — never before a move")


func test_second_turn_runs_a_normal_upkeep() -> void:
	# Asserted through `level`, not `xp.current`: WIS 10 gives xp_per_turn = 5
	# against a level-1 xp cap of exactly 5, so one real upkeep fills the pool
	# outright and OVERFLOW carries the remainder (0) — `current` lands back on
	# 0.0 and would read as "nothing happened". The level-up IS the income.
	var level_before: int = _entity.level
	_entity._on_turn_started(_entity)  # skipped
	assert_eq(_entity.level, level_before, "precondition: turn 1 changed nothing")
	_entity._on_turn_started(_entity)
	assert_gt(_entity.level, level_before,
			"the gate is first-turn only: turn 2 is an ordinary upkeep")


func test_first_turn_skips_pool_refill_too() -> void:
	# The whole body is gated, REFILLs included. Spending AP before the entity's
	# first turn is not a state the game can reach (the turn is what grants the
	# right to act), so this pins the mechanism, not a play scenario.
	var ap := _entity.stat_board.action_points
	ap.deplete(ap.current)
	_entity._on_turn_started(_entity)
	assert_eq(ap.current, 0.0, "first turn runs no upkeep at all, refills included")
	_entity._on_turn_started(_entity)
	assert_eq(ap.current, float(ap.get_value()), "turn 2 refills as normal")


func test_turns_taken_counts_served_turns_including_the_skipped_one() -> void:
	assert_eq(_entity.turns_taken, 0, "a spawned entity has been served no turns")
	_entity._on_turn_started(_entity)
	assert_eq(_entity.turns_taken, 1, "the skipped turn still counts as served")
	_entity._on_turn_started(_entity)
	assert_eq(_entity.turns_taken, 2)


func test_another_entitys_turn_does_not_burn_the_gate() -> void:
	var other := Entity.new()
	autofree(other)
	other.display_name = "Stranger"
	other.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child(other)
	await get_tree().process_frame

	# `turn_started` is a broadcast: every entity hears every turn and filters
	# on `entity != self`. The counter must only advance on our OWN turns.
	_entity._on_turn_started(other)
	assert_eq(_entity.turns_taken, 0, "someone else's turn is not one of ours")
	var xp_before: float = _entity.stat_board.xp.current
	_entity._on_turn_started(_entity)
	assert_eq(_entity.stat_board.xp.current, xp_before, "our own first turn is still the skipped one")
