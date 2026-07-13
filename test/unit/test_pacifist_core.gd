extends GutTest

## #39: the Pacifist gambit. Innate DP/MP are SET to 0; all mobility is bought
## with unspent AP converted to surplus at a steep ap_transfer_rate. Verifies
## the class statline AND that the zero-cap-plus-surplus state is coherent —
## the load-bearing #156 property (surplus lives outside the SET-short-circuit).

const _BOARD := preload("res://entity/default_entity_board.tres")
const _PACIFIST := preload("res://entity/core/pacifist_core.tres")

var _entity: Entity


func before_each() -> void:
	_entity = autofree(Entity.new())
	_entity.display_name = "Ascetic"
	_entity.stat_board = _BOARD.duplicate(true) as StatBoard
	_entity.core_class = _PACIFIST
	add_child_autofree(_entity)  # _ready duplicates the board, then core_class.apply()s onto it
	await get_tree().process_frame


func test_statline() -> void:
	var b := _entity.stat_board
	assert_eq(b.ap_transfer_rate.get_value(), 4.0, "rate 2 base + 2 = 4 (the 'factor 4' pacifist)")
	assert_eq(b.action_points.get_value(), 4.0, "more AP to convert (2 + 2)")
	assert_eq(b.armor.get_value(), 3.0, "armor to survive non-attacking turns")


func test_innate_mobility_is_set_to_zero() -> void:
	var b := _entity.stat_board
	assert_eq(b.movement_points.get_value(), 0.0, "innate MP cap SET 0")
	assert_eq(b.deallocation_points.get_value(), 0.0, "innate DP cap SET 0")


func test_restraint_buys_mobility() -> void:
	var b := _entity.stat_board
	# End a turn with 3 of 4 AP unused (attacked once).
	b.action_points.set_current(3.0)
	_entity._on_turn_ended(_entity)
	# Cap is 0, but the surplus bin lives outside the SET-short-circuit, so the
	# available budget is entirely purchased: roundi(3 unused × rate 4) = 12.
	assert_eq(b.movement_points.available(), 12, "mobility = unspent AP × rate, despite 0 cap")
	assert_eq(b.deallocation_points.available(), 12, "reshape budget bought the same way")


func test_spending_all_ap_anchors_the_entity() -> void:
	var b := _entity.stat_board
	# Attacked out the whole AP bar — 0 unused.
	b.action_points.set_current(0.0)
	_entity._on_turn_ended(_entity)
	assert_eq(b.movement_points.available(), 0, "no restraint, no motion — anchored")
	assert_eq(b.deallocation_points.available(), 0, "and no reshape budget either")
