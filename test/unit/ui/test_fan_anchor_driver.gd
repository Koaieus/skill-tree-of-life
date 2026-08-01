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
## computes it — [method FanAnchor.solve_route] fed every one of the unit's
## authored route knobs.
##
## None of those knobs is optional here. `derive_anchor` is only what
## `solve_route` reduces to under `Axis.AUTO`, so asserting against it agrees
## with the driver by coincidence for a unit that happens to author AUTO and
## then diverges the moment one declares an `arrival_axis` — which is exactly
## how this test went red when #308's forced axes landed. Same trap 8aa87d4
## documented for `anchor_slide`, one knob later: mirror the driver's call, do
## not re-derive a subset of it.
func _expected_anchor(unit: Node, trace: FanTrace, panel: FanPanel) -> Vector2:
	var fan_unit := unit as FanUnit
	var route := FanAnchor.solve_route(
		trace.from_point,
		FanAnchor.panel_rect_of(panel),
		trace.route_params(),
		fan_unit.arrival_axis,
		fan_unit.anchor_slide,
		fan_unit.trunk_length)
	return route.anchor


func test_moving_a_panel_rederives_its_trace_terminus() -> void:
	var inst := _FAN.instantiate()
	add_child(inst)
	autofree(inst)
	await get_tree().process_frame

	var unit := _find_unit(inst, "NodeStats")
	var trace: FanTrace = unit.get_node("%Trace")
	var panel: FanPanel = unit.get_node("%Panel")

	var original_to := trace.to_point

	# Drag the panel to a spot that demands a DIFFERENT anchor edge than the
	# authored position (moved from up-left to up-right of the trunk).
	panel.position = Vector2(220.0, -300.0)
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
