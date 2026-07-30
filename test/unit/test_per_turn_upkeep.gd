extends GutTest

## Declarative start-of-turn pool replenishment: PoolStatDef.per_turn_mode
## drives StatBoard.apply_per_turn_upkeep() in one sweep (no per-pool wiring in
## Entity._on_turn_started). REFILL pools go to cap; ADD pools gain their
## `<id>_per_turn` companion; NONE pools (skill_points, health) are untouched.

const _BOARD := preload("res://entity/default_entity_board.tres")

var _board: StatBoard


func before_each() -> void:
	_board = _BOARD.duplicate(true) as StatBoard


func _refill_pools() -> Array:
	return [_board.action_points, _board.deallocation_points, _board.movement_points]


func test_refill_pools_restore_to_cap() -> void:
	for pool in _refill_pools():
		pool.deplete(pool.current)
		assert_eq(pool.current, 0.0, "%s should drain to floor first" % pool.definition.id)
	_board.apply_per_turn_upkeep()
	for pool in _refill_pools():
		assert_eq(pool.current, float(pool.get_value()),
			"%s (REFILL) should return to cap on upkeep" % pool.definition.id)


func test_add_pool_gains_companion_value() -> void:
	# mana is ADD — it gains the value of its mana_per_turn companion.
	_board.mana_per_turn.base_value = 3.0
	_board.mana.deplete(_board.mana.current)
	_board.apply_per_turn_upkeep()
	assert_eq(_board.mana.current, 3.0, "mana should gain mana_per_turn (3) on upkeep")


func test_add_pool_clamps_to_cap() -> void:
	_board.mana_per_turn.base_value = 9999.0
	_board.mana.deplete(_board.mana.current)
	_board.apply_per_turn_upkeep()
	assert_eq(_board.mana.current, float(_board.mana.get_value()),
		"mana ADD should clamp at the cap, not overflow")


func test_add_pool_with_zero_rate_is_noop() -> void:
	_board.mana_per_turn.base_value = 0.0
	_board.mana.deplete(_board.mana.current)
	_board.apply_per_turn_upkeep()
	assert_eq(_board.mana.current, 0.0, "ADD with a 0 companion should add nothing")


func test_custom_pool_heals_wounds() -> void:
	# skill_points is CUSTOM: SkillPointStat._custom_turn_upkeep heals
	# wound_heal_per_turn worth of wounds (wounded -> current). wound() draws
	# from the `used` bin, so claim some allocated SP first.
	var sp := _board.skill_points
	_board.wound_heal_per_turn.base_value = 2.0
	sp.claim(3)        # max +3, lands in `used` (current unchanged)
	sp.wound(2)        # 2 of `used` -> `wounded`
	var current_before := sp.current
	assert_eq(sp.wounded, 2, "precondition: 2 wounded")

	_board.apply_per_turn_upkeep()

	assert_eq(sp.wounded, 0, "CUSTOM upkeep should heal 2 wounds (wounded -> 0)")
	assert_eq(sp.current, current_before + 2.0, "healed wounds should land back in current")


func test_none_pool_is_untouched() -> void:
	# xp is ADD, mana is ADD, skill_points is CUSTOM — initiative is the NONE
	# pool: it's tick-driven by TurnManager, never by the turn-start sweep.
	_board.initiative.deplete(_board.initiative.current)
	var initiative_current := _board.initiative.current
	_board.apply_per_turn_upkeep()
	assert_eq(_board.initiative.current, initiative_current,
		"initiative (NONE) must not be touched by the upkeep sweep")


func test_add_pool_can_name_its_companion_stat() -> void:
	# health is ADD via an explicit per_turn_stat_id (`core_healing`, D-25)
	# rather than the `<id>_per_turn` convention — the override must resolve.
	assert_eq(_board.health.pool_definition.resolved_per_turn_stat_id(), &"core_healing")
	assert_eq(_board.mana.pool_definition.resolved_per_turn_stat_id(), &"mana_per_turn",
		"pools without an override keep the <id>_per_turn convention")
