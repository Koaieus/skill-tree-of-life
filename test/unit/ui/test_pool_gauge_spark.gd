extends GutTest

## The segment sweep (#882): a battery gauge never jumps to a new value. Its
## DISPLAYED value tweens there linearly at `cell_step_time` per cell, so a
## 4-point spend recedes one cell at a time over 4T and a refill grows back the
## same way, while the cell the edge is crossing burns at `spark_stops`.
##
## What is worth pinning here is not the look — that is judged in a running
## sandbox — but the rules the look depends on and that regress silently: the
## displayed value lags the model at a constant per-cell rate, a surplus spend
## sweeps its trailing cell through the same plumbing, a (re)bind snaps instead
## of sweeping, and the SP bar's runs sweep the same way.

const _PANEL := preload("res://ui/hud/turn_resources_panel/turn_resources_panel.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
## Per-cell step used by every test here, so the timings below don't drift
## with the authored scene value.
const _STEP := 0.2
## A tween the sweep's own tween_callback spawns (the cool tween, the next
## bin's sweep) is created MID advance() and so first moves on the NEXT call —
## step past the sweep's own boundary, never exactly onto it, so the spawn
## happens inside the step that lands the assert.
const _HAIR := 0.001

var _panel: TurnResourcesPanel
var _board: EntityStatBoard


func before_each() -> void:
	_panel = _PANEL.instantiate()
	add_child_autofree(_panel)
	_board = _BOARD.duplicate(true) as EntityStatBoard
	_mp_gauge().clock.manual = true
	_sp_bar().clock.manual = true
	await get_tree().process_frame


func _mp_gauge() -> SurplusPoolGauge:
	return _panel.get_node(^"%MPGauge") as SurplusPoolGauge


func _sp_bar() -> CompositeBarGauge:
	return _panel.get_node(^"%SPBar") as CompositeBarGauge


func _uniform(gauge: ColorRect, param: StringName) -> Variant:
	return (gauge.material as ShaderMaterial).get_shader_parameter(param)


func _bind_mp(cap: float, current: float, surplus: int = 0) -> SurplusPoolGauge:
	var mp := _board.movement_points
	mp.base_value = cap
	mp.set_current(current)
	if surplus > 0:
		mp.set_surplus(surplus)
	_panel.bind(_board)
	var gauge := _mp_gauge()
	gauge.cell_step_time = _STEP
	return gauge


func test_spending_sweeps_one_cell_at_a_time() -> void:
	var gauge := _bind_mp(5.0, 5.0)
	await get_tree().process_frame

	_board.movement_points.set_current(1.0)
	assert_eq(gauge.current, 1.0, "the model value lands at once")
	assert_almost_eq(gauge.shown_current, 5.0, 0.01, "…but the display starts where it was")
	assert_almost_eq(float(_uniform(gauge, &"current")), 5.0, 0.01, "and so does the shader")
	assert_eq(float(_uniform(gauge, &"spark_energy")), 1.0, "the crossing cell burns for the whole sweep")
	assert_eq(float(_uniform(gauge, &"spark_out")), 1.0, "spent cells are leaving")

	gauge.clock.advance(_STEP * 1.5)
	assert_between(gauge.shown_current, 3.2, 3.8,
			"after 1.5 steps the edge is halfway through the fourth cell — cell 5 is gone, cell 4 is receding")

	gauge.clock.advance(_STEP * 3.0)
	assert_almost_eq(gauge.shown_current, 1.0, 0.01, "four cells take four steps")
	assert_almost_eq(float(_uniform(gauge, &"current")), 1.0, 0.01)


func test_replenishing_sweeps_back_the_same_way() -> void:
	var gauge := _bind_mp(5.0, 1.0)
	await get_tree().process_frame

	_board.movement_points.set_current(4.0)
	assert_almost_eq(gauge.shown_current, 1.0, 0.01, "the display starts where it was")
	assert_eq(float(_uniform(gauge, &"spark_out")), 0.0, "arriving cells are not leaving")

	gauge.clock.advance(_STEP * 1.5)
	assert_between(gauge.shown_current, 2.2, 2.8, "growing left to right, one cell per step")

	gauge.clock.advance(_STEP * 2.0)
	assert_almost_eq(gauge.shown_current, 4.0, 0.01)


func test_the_lift_cools_after_the_sweep() -> void:
	var gauge := _bind_mp(5.0, 5.0)
	gauge.spark_time = 0.1
	await get_tree().process_frame

	_board.movement_points.set_current(4.0)
	gauge.clock.advance(_STEP * 0.5)
	assert_eq(float(_uniform(gauge, &"spark_energy")), 1.0, "hot while sweeping")
	gauge.clock.advance(_STEP * 0.5 + _HAIR)  # lands the sweep, spawns the cool tween
	gauge.clock.advance(0.2)  # the cool tween only starts moving on the NEXT advance
	assert_almost_eq(float(_uniform(gauge, &"spark_energy")), 0.0, 0.01, "cooled once it landed")


## A second spend while the first is still sweeping continues from wherever
## the display is — never snaps to the first target and restarts.
func test_a_spend_mid_sweep_continues_from_the_displayed_value() -> void:
	var gauge := _bind_mp(5.0, 5.0)
	await get_tree().process_frame

	_board.movement_points.set_current(3.0)
	gauge.clock.advance(_STEP * 1.0)
	var mid: float = gauge.shown_current
	assert_between(mid, 3.7, 4.3, "one cell in")
	_board.movement_points.set_current(1.0)
	assert_almost_eq(gauge.shown_current, mid, 0.05, "no snap on the second spend")
	gauge.clock.advance(_STEP * 3.5)
	assert_almost_eq(gauge.shown_current, 1.0, 0.01, "and it arrives at the new target")


## The one the surplus bin exists to break: MP is spent surplus-first, so the
## cell that leaves is a TRAILING cell past the cap, not a `current` cell — and
## it sweeps through the same plumbing.
func test_spending_surplus_sweeps_the_trailing_cell() -> void:
	var gauge := _bind_mp(2.0, 2.0, 2)
	await get_tree().process_frame

	_board.movement_points.deplete(1.0)
	assert_eq(roundi(_board.movement_points.current), 2, "the spend came out of surplus, leaving `current` alone")
	assert_almost_eq(gauge.shown_current, 2.0, 0.01, "`current` never moved")
	assert_almost_eq(gauge.shown_surplus, 2.0, 0.01, "the trailing cell starts full")

	gauge.clock.advance(_STEP * 0.5)
	assert_between(gauge.shown_surplus, 1.2, 1.8, "…and recedes over one step")
	assert_between(float(_uniform(gauge, &"surplus")), 1.2, 1.8, "the shader sees the fractional cell")

	gauge.clock.advance(_STEP * 0.8)
	assert_almost_eq(gauge.shown_surplus, 1.0, 0.01)


## MP is spent surplus-first, so a big move empties the trailing gold cells and
## then bites into `current` — two signals on two properties. The spec: the
## next cell never starts before the one before it is gone, so the second sweep
## WAITS for the first (surplus fires first), and the strip keeps every slot
## the sweep passes through until the display lands.
func test_a_spend_across_both_bins_sweeps_them_in_turn() -> void:
	var gauge := _bind_mp(3.0, 3.0, 2)
	await get_tree().process_frame

	_board.movement_points.deplete(4.0)
	assert_eq(roundi(_board.movement_points.current), 1, "2 from surplus, 2 from current")
	assert_almost_eq(float(_uniform(gauge, &"surplus_slots")), 2.0, 0.01, "both gold slots stay laid out")

	gauge.clock.advance(_STEP * 1.5)
	assert_between(gauge.shown_surplus, 0.2, 0.8, "the surplus is receding…")
	assert_almost_eq(gauge.shown_current, 3.0, 0.01, "…and `current` has not started")
	assert_almost_eq(float(_uniform(gauge, &"surplus_slots")), 2.0, 0.01, "no re-layout mid-sweep")

	gauge.clock.advance(_STEP * 0.5 + _HAIR)  # lands the surplus sweep, spawns the current sweep
	gauge.clock.advance(_STEP * 1.0)  # the current sweep only starts moving on the NEXT advance
	assert_almost_eq(gauge.shown_surplus, 0.0, 0.01, "surplus gone")
	assert_between(gauge.shown_current, 1.8, 2.7, "now `current` recedes")
	assert_almost_eq(float(_uniform(gauge, &"surplus_slots")), 0.0, 0.01, "the gold slots left once the display landed")

	gauge.clock.advance(_STEP * 2.0)
	assert_almost_eq(gauge.shown_current, 1.0, 0.01)


## A hot-seat handover repaints the gauge from a different hero's pools. That is
## a bind, not a spend — nothing sweeps, nothing burns.
func test_a_rebind_snaps_instead_of_sweeping() -> void:
	var gauge := _bind_mp(4.0, 4.0)
	await get_tree().process_frame

	# Rebind MID-sweep: the old hero's sweep must not keep driving the display.
	_board.movement_points.set_current(2.0)
	gauge.clock.advance(_STEP * 0.5)

	var other := _BOARD.duplicate(true) as EntityStatBoard
	other.movement_points.base_value = 4.0
	other.movement_points.set_current(1.0)
	_panel.bind(other)

	gauge = _mp_gauge()
	assert_almost_eq(gauge.shown_current, 1.0, 0.01, "binding a hero with fewer points must not read as a spend")
	assert_eq(float(_uniform(gauge, &"spark_energy")), 0.0, "…and must not burn")
	gauge.clock.advance(_STEP * 1.0)
	assert_almost_eq(gauge.shown_current, 1.0, 0.01, "the abandoned sweep stays abandoned")


# ── The Skill Points bar ────────────────────────────────────────────────────
# A different widget with a different model — four proportional buckets instead
# of one current/max pool — but the same sweep, off the same GaugeSpark.

func test_spending_a_skill_point_sweeps_the_to_spend_run() -> void:
	var sp := _board.skill_points
	sp.base_value = 10.0
	sp.set_current(6.0)
	_panel.bind(_board)
	var bar := _sp_bar()
	bar.cell_step_time = _STEP
	await get_tree().process_frame

	sp.spend(1)
	assert_almost_eq(bar.shown_fractions.x, 0.6, 0.001, "the display starts where it was")
	assert_eq(float(_uniform(bar, &"spark_edge")), 0.0, "the to-spend boundary is the one crossing")
	assert_eq(float(_uniform(bar, &"spark_out")), 1.0, "a spent point is leaving")

	bar.clock.advance(_STEP * 0.5)
	assert_between(bar.shown_fractions.x, 0.52, 0.58, "half a cell in")
	assert_between((_uniform(bar, &"fractions") as Vector3).x, 0.52, 0.58, "the shader draws the partial cell")

	bar.clock.advance(_STEP * 0.8)
	assert_almost_eq(bar.shown_fractions.x, 0.5, 0.001)


## The one the panel used to miss entirely: a forced deallocation moves
## used -> wounded, which touches neither `current` nor `value`.
func test_a_wound_repaints_and_sweeps_the_wounded_run() -> void:
	var sp := _board.skill_points
	sp.base_value = 10.0
	sp.set_current(4.0)
	_panel.bind(_board)
	var bar := _sp_bar()
	bar.cell_step_time = _STEP
	await get_tree().process_frame

	sp.wound(2)
	assert_eq(bar.wounded, 2.0, "the bar heard the wound at all")
	assert_eq(float(_uniform(bar, &"spark_energy")), 1.0, "…and burns")
	assert_eq(float(_uniform(bar, &"spark_edge")), 1.0,
			"the allocated|wounded boundary is the one crossing — the wound grows from the right")
	assert_eq(float(_uniform(bar, &"spark_out")), 0.0, "wounded cells are arriving")

	bar.clock.advance(_STEP * 1.0)
	assert_between(bar.shown_fractions.y, 0.07, 0.13, "one of two cells in")

	bar.clock.advance(_STEP * 1.3)
	assert_almost_eq(bar.shown_fractions.y, 0.2, 0.001)


func test_binding_the_sp_bar_does_not_sweep() -> void:
	var sp := _board.skill_points
	sp.base_value = 10.0
	sp.set_current(4.0)
	_panel.bind(_board)
	await get_tree().process_frame

	assert_eq(float(_uniform(_sp_bar(), &"spark_energy")), 0.0, "a bind paints; it does not spend")
	assert_almost_eq(_sp_bar().shown_fractions.x, 0.4, 0.001)


## The trailing runs are mirrored: a wound GROWS right-to-left (its boundary
## `b1` walks left into the allocated headroom) and a heal DEPLETES left-to-
## right (the same boundary walks back). There is no flip to author — the
## partial cell is whatever side of the moving boundary the run is on — but
## the direction flag must read the mirror correctly, or the lift would tail
## the wrong cell.
func test_healing_a_wound_depletes_left_to_right() -> void:
	var sp := _board.skill_points
	sp.base_value = 10.0
	sp.set_current(4.0)
	sp.wound(2)
	_panel.bind(_board)
	var bar := _sp_bar()
	bar.cell_step_time = _STEP
	await get_tree().process_frame

	sp.heal(1)
	assert_eq(float(_uniform(bar, &"spark_edge")), 1.0, "the allocated|wounded boundary moves")
	assert_eq(float(_uniform(bar, &"spark_out")), 1.0, "a healed cell is leaving")

	bar.clock.advance(_STEP * 0.5)
	assert_between(bar.shown_fractions.y, 0.12, 0.18,
			"half a cell healed: the LEFTMOST wounded cell is receding toward the right")

	bar.clock.advance(_STEP * 0.8)
	assert_almost_eq(bar.shown_fractions.y, 0.1, 0.001)
