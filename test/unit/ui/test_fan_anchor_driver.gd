extends GutTest

## Tooltip V2 (#226) — FanAnchorDriver is what makes Decision 4 live in the
## editor: dragging a panel re-derives its trace terminus with ZERO
## re-authoring. This proves the re-derivation actually runs (each frame, or
## on demand via [method FanAnchorDriver.reroute]) rather than only on the
## authored starting layout — the gap a purely-static test of [FanAnchor]
## itself couldn't catch.

const _FAN := preload("res://ui/tooltip_fan/fan.tscn")


func _find_unit(root: Node, unit_name: String) -> Node:
	return root.find_child(unit_name, true, false)


## The terminus the driver OUGHT to have derived, computed the way the driver
## computes it — [method FanAnchor.solve_route] fed the trace's own
## [method FanTrace.route_params], which carries the fan-wide trunk length the
## driver wrote onto it. Mirror the driver's call, never a hand-built subset of
## it: a param dict without `trunk_px` describes a route nobody draws.
func _expected_anchor(_unit: Node, trace: FanTrace, panel: FanPanel) -> Vector2:
	var route := FanAnchor.solve_route(
		trace.from_point,
		FanAnchor.panel_rect_of(panel),
		trace.route_params())
	return route.anchor


func test_moving_a_unit_rederives_its_trace_terminus() -> void:
	var inst := _FAN.instantiate()
	add_child(inst)
	autofree(inst)
	await get_tree().process_frame

	var unit := _find_unit(inst, "NodeStats")
	var trace: FanTrace = unit.get_node("%Trace")
	var panel: FanPanel = unit.get_node("%Panel")

	var original_to := trace.to_point

	# Drag the unit (the authored rest; its panel is the solver's) to a spot
	# that demands a DIFFERENT anchor edge (up-left of the trunk to up-right).
	(unit as Node2D).position = Vector2(220.0, -300.0)
	await get_tree().process_frame

	var expected: Vector2 = _expected_anchor(unit, trace, panel)
	assert_ne(trace.to_point, original_to, "moving the panel must change the derived terminus")
	assert_almost_eq(trace.to_point.x, expected.x, 0.01)
	assert_almost_eq(trace.to_point.y, expected.y, 0.01)


func test_reroute_can_be_called_directly_without_waiting_a_frame() -> void:
	var inst := _FAN.instantiate()
	add_child(inst)
	autofree(inst)
	await get_tree().process_frame

	var unit := _find_unit(inst, "Addons")
	var trace: FanTrace = unit.get_node("%Trace")
	var panel: FanPanel = unit.get_node("%Panel")

	panel.position = Vector2(300.0, 40.0)
	(inst as FanAnchorDriver).reroute(unit)

	var expected: Vector2 = _expected_anchor(unit, trace, panel)
	assert_almost_eq(trace.to_point.x, expected.x, 0.01, "reroute() must match a fresh derive")
	assert_almost_eq(trace.to_point.y, expected.y, 0.01, "reroute() must match a fresh derive")


# --- #307 A/B: clock pins + spatial ordering ----------------------------------

const _STEP := 30.0
const _MAX_ARC := 120.0


func _angle_of(offset: Vector2) -> float:
	# Degrees clockwise from 12 o'clock, matching pin_offset's own convention.
	return rad_to_deg(atan2(offset.x, -offset.y))


func test_three_pins_sit_at_eleven_twelve_and_one_oclock() -> void:
	var angles: Array[float] = []
	for i in range(3):
		angles.append(_angle_of(FanAnchorDriver.pin_offset(i, 3, 32.0, _STEP, _MAX_ARC)))
	assert_almost_eq(angles[0], -30.0, 0.01, "11 o'clock")
	assert_almost_eq(angles[1], 0.0, 0.01, "12 o'clock")
	assert_almost_eq(angles[2], 30.0, 0.01, "1 o'clock")


func test_four_pins_sit_at_the_half_hours_around_twelve() -> void:
	var angles: Array[float] = []
	for i in range(4):
		angles.append(_angle_of(FanAnchorDriver.pin_offset(i, 4, 32.0, _STEP, _MAX_ARC)))
	assert_almost_eq(angles[0], -45.0, 0.01, "10:30")
	assert_almost_eq(angles[1], -15.0, 0.01, "11:30")
	assert_almost_eq(angles[2], 15.0, 0.01, "12:30")
	assert_almost_eq(angles[3], 45.0, 0.01, "1:30")


func test_the_spread_is_always_symmetric_about_twelve_oclock() -> void:
	for n in range(1, 8):
		var first := _angle_of(FanAnchorDriver.pin_offset(0, n, 32.0, _STEP, _MAX_ARC))
		var last := _angle_of(FanAnchorDriver.pin_offset(n - 1, n, 32.0, _STEP, _MAX_ARC))
		assert_almost_eq(first, -last, 0.01, "n=%d must straddle 12 o'clock evenly" % n)


func test_the_step_compresses_rather_than_the_arc_exceeding_the_cap() -> void:
	# 7 pins at a 30 step would span 180; the cap is 120, so the step shrinks.
	var n := 7
	var first := _angle_of(FanAnchorDriver.pin_offset(0, n, 32.0, _STEP, _MAX_ARC))
	var last := _angle_of(FanAnchorDriver.pin_offset(n - 1, n, 32.0, _STEP, _MAX_ARC))
	assert_almost_eq(last - first, _MAX_ARC, 0.01, "total spread is clamped to the cap")
	var a0 := _angle_of(FanAnchorDriver.pin_offset(1, n, 32.0, _STEP, _MAX_ARC))
	assert_true(a0 - first < _STEP, "and the per-pin step compressed to fit")


func test_every_pin_sits_on_the_given_radius() -> void:
	for n in range(1, 6):
		for i in range(n):
			assert_almost_eq(FanAnchorDriver.pin_offset(i, n, 48.0, _STEP, _MAX_ARC).length(), 48.0, 0.01)


func test_a_lone_pin_points_straight_up() -> void:
	assert_eq(FanAnchorDriver.pin_offset(0, 1, 32.0, _STEP, _MAX_ARC), Vector2(0.0, -32.0))


# --- the driver runs FanLayout -------------------------------------------

func _fan() -> FanAnchorDriver:
	var inst := _FAN.instantiate()
	add_child(inst)
	autofree(inst)
	return inst as FanAnchorDriver


## Bloom: a unit going HIDDEN → IN shows its panel centred on the trunk top —
## the fan-space form of [method FanAnchorDriver.trunk_top_of] — before a
## single frame has run, while the solver's body stays on the solved spot.
func test_bloom_seeds_at_the_trunk_top() -> void:
	var driver := _fan()
	driver.refresh()
	var unit := _find_unit(driver, "Owner") as FanUnit
	var panel := unit.get_node("%Panel") as FanPanel
	var trace: FanTrace = unit.get_node("%Trace")
	var top := driver.trunk_top_of(unit) + trace.position + unit.position
	var solved := driver.body_of(unit).position
	assert_ne(FanAnchor.panel_rect_of(panel).get_center() + unit.position, top,
		"precondition: the settled panel is not already at the trunk top")
	unit.play_in()
	var centre := FanAnchor.panel_rect_of(panel).get_center() + unit.position
	assert_almost_eq(centre.x, top.x, 0.01, "bloom starts at the trunk top")
	assert_almost_eq(centre.y, top.y, 0.01, "bloom starts at the trunk top")
	assert_eq(driver.body_of(unit).position, solved, "the leg is visual — the solver body never moves")


func test_trunk_top_is_the_pin_plus_the_fan_wide_trunk() -> void:
	var driver := _fan()
	driver.trunk_length = 55.0
	driver.refresh()
	var unit := _find_unit(driver, "IdChip")
	var trace: FanTrace = unit.get_node("%Trace")
	var expected := trace.from_point + trace.trunk_dir.normalized() * 55.0
	assert_almost_eq(driver.trunk_top_of(unit).x, expected.x, 0.001)
	assert_almost_eq(driver.trunk_top_of(unit).y, expected.y, 0.001)


## `refresh()` settles: one more frame after it moves nothing.
func test_refresh_settles_the_layout() -> void:
	var driver := _fan()
	driver.refresh()
	var before := {}
	for unit in driver.units_in_fan_order():
		before[unit.name] = (unit.get_node("%Panel") as FanPanel).position
	driver._process(1.0 / 60.0)
	for unit in driver.units_in_fan_order():
		var now := (unit.get_node("%Panel") as FanPanel).position
		assert_almost_eq(now.distance_to(before[unit.name]), 0.0, 0.1,
			"%s moved after refresh() — it did not converge" % unit.name)


## The solved body position IS the panel's live rect, in fan space.
func test_the_solved_position_is_written_onto_the_panel() -> void:
	var driver := _fan()
	driver.refresh()
	for unit in driver.units_in_fan_order():
		var rect := FanAnchor.panel_rect_of(unit.get_node("%Panel") as FanPanel)
		var body := driver.body_of(unit)
		assert_almost_eq(rect.position.x + (unit as Node2D).position.x, body.position.x, 0.01)
		assert_almost_eq(rect.position.y + (unit as Node2D).position.y, body.position.y, 0.01)


## Every unit blooming in the same frame — the worst case of the stagger —
## lands every panel exactly on the warm layout `refresh()` converged to: the
## leg is visual, so the screen never settles into an equilibrium of its own.
func test_a_full_bloom_lands_on_the_warm_layout() -> void:
	var driver := _fan()
	driver.refresh()
	var warm := {}
	for unit in driver.units_in_fan_order():
		warm[unit.name] = driver.body_of(unit).position
	for unit in driver.units_in_fan_order():
		(unit as FanUnit).play_in()
	for _frame in 120:
		driver._process(1.0 / 60.0)
	for unit in driver.units_in_fan_order():
		var rect := FanAnchor.panel_rect_of(unit.get_node("%Panel") as FanPanel)
		var shown := rect.position + (unit as Node2D).position
		var solved := driver.body_of(unit).position
		assert_almost_eq(shown.distance_to(solved), 0.0, 0.1,
			"%s landed at %s, not on its solved spot %s" % [unit.name, shown, solved])
		# The contact equilibrium creeps sub-pixel past settle()'s epsilon; the
		# bloom does not add to that.
		assert_almost_eq(solved.distance_to(warm[unit.name]), 0.0, 2.0,
			"%s's solved spot %s wandered from the warm layout %s" % [unit.name, solved, warm[unit.name]])


## Mid-leg the wire chases the FLYING panel, not the empty solved spot.
func test_mid_bloom_the_trace_ends_on_the_flying_panel() -> void:
	var driver := _fan()
	driver.refresh()
	var unit := _find_unit(driver, "Owner") as FanUnit
	var panel := unit.get_node("%Panel") as FanPanel
	var trace: FanTrace = unit.get_node("%Trace")
	unit.play_in()
	for _frame in 3:
		driver._process(1.0 / 60.0)
	var rect := FanAnchor.panel_rect_of(panel)
	assert_gt((rect.position + unit.position).distance_to(driver.body_of(unit).position), 1.0,
		"precondition: the panel is still in flight")
	assert_true(rect.grow(0.01).has_point(trace.to_point) and not FanAnchor.is_inside(trace.to_point, rect),
		"to_point %s must sit on the flying panel's edge %s" % [trace.to_point, rect])
