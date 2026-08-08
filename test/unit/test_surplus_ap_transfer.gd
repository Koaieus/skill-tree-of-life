extends GutTest

## #152: at turn end, each unused action point transfers into the following
## turn's DP/MP surplus, scaled by the `ap_transfer_rate` board stat
## (Entity._on_turn_ended → _transfer_unused_ap_to_surplus). boost =
## roundi(unused_ap × rate). set_surplus overwrites, so a turn ending with 0
## unused AP self-clears the boost.

const _BOARD := preload("res://entity/default_entity_board.tres")

var _entity: Entity


func before_each() -> void:
	_entity = autofree(Entity.new())
	_entity.display_name = "Wanderer"
	_entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child_autofree(_entity)  # _ready duplicates the board again; read it back after
	await get_tree().process_frame


func _set_rate(rate: float) -> void:
	_entity.stat_board.ap_transfer_rate.base_value = rate


func _end_turn_with_unused_ap(unused: int) -> void:
	var board := _entity.stat_board
	# Drain AP to the cap, then set the unused remainder.
	board.action_points.set_current(float(unused))
	_entity._on_turn_ended(_entity)


func test_default_rate_is_two() -> void:
	# The default board ships ap_transfer_rate = 2 (#152 tuning: symmetric with
	# DP/MP base 3, so 2 unused AP → 3→7 both pools).
	assert_eq(_entity.stat_board.ap_transfer_rate.get_value(), 2.0, "default rate = 2")


func test_boost_is_unused_ap_times_rate() -> void:
	_set_rate(2.0)
	_end_turn_with_unused_ap(2)
	assert_eq(_entity.stat_board.deallocation_points.surplus, 4, "DP surplus = unused AP × rate")
	assert_eq(_entity.stat_board.movement_points.surplus, 4, "MP surplus = unused AP × rate")


func test_rate_scales_the_boost() -> void:
	# The stat is the whole knob: a class-identity modifier on it changes the
	# conversion with no code path of its own.
	_set_rate(1.0)
	_end_turn_with_unused_ap(2)
	assert_eq(_entity.stat_board.movement_points.surplus, 2, "rate 1 → 1:1 conversion")


func test_zero_rate_grants_no_surplus() -> void:
	# The Berserker pole (#39): converts nothing, spends everything.
	_set_rate(0.0)
	_end_turn_with_unused_ap(2)
	assert_eq(_entity.stat_board.deallocation_points.surplus, 0, "rate 0 → no surplus even with unused AP")
	assert_eq(_entity.stat_board.movement_points.surplus, 0)


func test_surplus_extends_available_budget() -> void:
	_set_rate(1.0)
	var dp := _entity.stat_board.deallocation_points
	var cap := int(dp.value)
	_end_turn_with_unused_ap(2)
	assert_eq(dp.available(), cap + 2, "available budget = cap + surplus")


func test_idle_ap_turn_clears_prior_surplus() -> void:
	_set_rate(2.0)
	_end_turn_with_unused_ap(2)
	assert_eq(_entity.stat_board.movement_points.surplus, 4)
	# Next turn ends with all AP spent (0 unused) — set_surplus(0) overwrites.
	_end_turn_with_unused_ap(0)
	assert_eq(_entity.stat_board.movement_points.surplus, 0, "spent-AP turn self-clears surplus")
	assert_eq(_entity.stat_board.deallocation_points.surplus, 0)
