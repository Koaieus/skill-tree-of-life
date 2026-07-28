extends GutTest

## Tooltip V2 (#226) — FanAnchorDriver is what makes Decision 4 live in the
## editor: dragging a panel re-derives its trace terminus with ZERO
## re-authoring. This proves the re-derivation actually runs (each frame, or
## on demand via [method FanAnchorDriver.reroute]) rather than only on the
## authored starting layout — the gap a purely-static test of [FanAnchor]
## itself couldn't catch.

const _UNOWNED := preload("res://ui/tooltip_fan/variants/unowned.tscn")


func _find_unit(root: Node, unit_name: String) -> Node:
	return root.find_child(unit_name, true, false)


func test_moving_a_panel_rederives_its_trace_terminus() -> void:
	var inst := _UNOWNED.instantiate()
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

	var expected := FanAnchor.derive_anchor(
		trace.from_point, FanAnchor.panel_rect_of(panel), trace.trunk_dir, trace.bend_start)
	assert_ne(trace.to_point, original_to, "moving the panel must change the derived terminus")
	assert_almost_eq(trace.to_point.x, expected.x, 0.01)
	assert_almost_eq(trace.to_point.y, expected.y, 0.01)


func test_reroute_can_be_called_directly_without_waiting_a_frame() -> void:
	var inst := _UNOWNED.instantiate()
	add_child(inst)
	autofree(inst)
	await get_tree().process_frame

	var unit := _find_unit(inst, "Addons")
	var trace: FanTrace = unit.get_node("%Trace")
	var panel: FanPanel = unit.get_node("%Panel")

	panel.position = Vector2(300.0, 40.0)
	(inst as FanAnchorDriver).reroute(unit)

	var expected := FanAnchor.derive_anchor(
		trace.from_point, FanAnchor.panel_rect_of(panel), trace.trunk_dir, trace.bend_start)
	assert_almost_eq(trace.to_point.x, expected.x, 0.01)
	assert_almost_eq(trace.to_point.y, expected.y, 0.01)
