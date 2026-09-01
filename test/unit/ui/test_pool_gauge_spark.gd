extends GutTest

## The ignition spark: a battery cell burns at `spark_stops` the moment it
## arrives or leaves, then cools to the resting `glow_stops`.
##
## What is worth pinning here is not the look — that is judged in a running
## sandbox — but the three rules the look depends on and that regress silently:
## the band is in RENDERED STRIP CELLS (so a Movement point spent out of the
## surplus bin ignites a trailing cell, not a `current` one), a (re)bind snaps
## instead of igniting, and the HUD only ever ignites off a pool that already
## moved.

const _PANEL := preload("res://ui/hud/turn_resources_panel/turn_resources_panel.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _panel: TurnResourcesPanel
var _board: EntityStatBoard


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)
	_board = _BOARD.duplicate(true) as EntityStatBoard
	await get_tree().process_frame


func _mp_gauge() -> SurplusPoolGauge:
	return _panel.get_node(^"%MPGauge") as SurplusPoolGauge


func _uniform(gauge: PoolGauge, param: StringName) -> Variant:
	return (gauge.material as ShaderMaterial).get_shader_parameter(param)


func test_spending_current_ignites_the_cells_it_left() -> void:
	var mp := _board.movement_points
	mp.base_value = 4.0
	mp.set_current(4.0)
	_panel.bind(_board)
	await get_tree().process_frame

	mp.set_current(3.0)
	await get_tree().process_frame

	var gauge := _mp_gauge()
	assert_almost_eq(float(_uniform(gauge, &"spark_lo")), 3.0, 0.01,
			"band starts at the cell the pool fell to")
	assert_almost_eq(float(_uniform(gauge, &"spark_hi")), 4.0, 0.01,
			"…and ends at the cell it left")
	assert_eq(float(_uniform(gauge, &"spark_out")), 1.0, "spent cells are outgoing")
	assert_gt(float(_uniform(gauge, &"spark_energy")), 0.0, "the cell is burning")


func test_replenishing_ignites_inward() -> void:
	var mp := _board.movement_points
	mp.base_value = 4.0
	mp.set_current(1.0)
	_panel.bind(_board)
	await get_tree().process_frame

	mp.set_current(4.0)
	await get_tree().process_frame

	var gauge := _mp_gauge()
	assert_almost_eq(float(_uniform(gauge, &"spark_lo")), 1.0, 0.01, "band starts where it was")
	assert_almost_eq(float(_uniform(gauge, &"spark_hi")), 4.0, 0.01, "…and covers what arrived")
	assert_eq(float(_uniform(gauge, &"spark_out")), 0.0, "arriving cells are not outgoing")


## The one the surplus bin exists to break: MP is spent surplus-first, so the
## cell that leaves is a TRAILING cell past the cap, not a `current` cell.
func test_spending_surplus_ignites_a_trailing_cell() -> void:
	var mp := _board.movement_points
	mp.base_value = 2.0
	mp.set_current(2.0)
	mp.set_surplus(2)
	_panel.bind(_board)
	await get_tree().process_frame

	mp.deplete(1.0)
	await get_tree().process_frame

	var gauge := _mp_gauge()
	assert_eq(roundi(mp.current), 2, "the spend came out of surplus, leaving `current` alone")
	assert_almost_eq(float(_uniform(gauge, &"spark_lo")), 3.0, 0.01,
			"cap 2 + 1 remaining surplus = strip cell 3")
	assert_almost_eq(float(_uniform(gauge, &"spark_hi")), 4.0, 0.01,
			"…through the cell that was spent")
	assert_eq(float(_uniform(gauge, &"spark_out")), 1.0, "a spent surplus cell is outgoing")


## A hot-seat handover repaints the gauge from a different hero's pools. That is
## a bind, not a spend — nothing may ignite.
func test_a_rebind_snaps_instead_of_igniting() -> void:
	var mp := _board.movement_points
	mp.base_value = 4.0
	mp.set_current(4.0)
	_panel.bind(_board)
	await get_tree().process_frame

	var other := _BOARD.duplicate(true) as EntityStatBoard
	other.movement_points.base_value = 4.0
	other.movement_points.set_current(1.0)
	_panel.bind(other)
	await get_tree().process_frame

	assert_eq(float(_uniform(_mp_gauge(), &"spark_energy")), 0.0,
			"binding a hero with fewer points must not read as a spend")
