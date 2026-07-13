extends GutTest

## #152: at turn end, each unused action point transfers 1:1 into the following
## turn's DP/MP surplus (Entity._on_turn_ended → _transfer_unused_ap_to_surplus).
## set_surplus overwrites, so a turn ending with 0 unused AP self-clears the boost.

const _BOARD := preload("res://entity/default_entity_board.tres")

var _entity: Entity


func before_each() -> void:
	_entity = autofree(Entity.new())
	_entity.display_name = "Wanderer"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	add_child_autofree(_entity)  # _ready duplicates the board again; read it back after
	await get_tree().process_frame


func _end_turn_with_unused_ap(unused: int) -> void:
	var board := _entity.stat_board
	# Drain AP to the cap, then set the unused remainder.
	board.action_points.set_current(float(unused))
	_entity._on_turn_ended(_entity)


func test_unused_ap_grants_surplus_on_dp_and_mp() -> void:
	_end_turn_with_unused_ap(2)
	assert_eq(_entity.stat_board.deallocation_points.surplus, 2, "DP surplus = unused AP")
	assert_eq(_entity.stat_board.movement_points.surplus, 2, "MP surplus = unused AP")


func test_surplus_extends_available_budget() -> void:
	var dp := _entity.stat_board.deallocation_points
	var cap := int(dp.value)
	_end_turn_with_unused_ap(2)
	assert_eq(dp.available(), cap + 2, "available budget = cap + surplus")


func test_idle_ap_turn_clears_prior_surplus() -> void:
	_end_turn_with_unused_ap(2)
	assert_eq(_entity.stat_board.movement_points.surplus, 2)
	# Next turn ends with all AP spent (0 unused) — set_surplus(0) overwrites.
	_end_turn_with_unused_ap(0)
	assert_eq(_entity.stat_board.movement_points.surplus, 0, "spent-AP turn self-clears surplus")
	assert_eq(_entity.stat_board.deallocation_points.surplus, 0)
