extends GutTest

## Tooltip V2 radar label bounding-box fix (epic #159 Phase 0). Axis labels
## used to be placed at _axis_point(i, 1.16) -- 116% of the plot radius,
## outside the plotted circle -- and drawn via draw_string offset by
## Vector2(20, -4) with width=40. That put the label text box outside the
## Control's own rect, making the widget hard to position in a layout.
##
## Fix moved label placement to a dedicated _label_anchor(i) helper, bounded
## via `label_margin` so the draw_string box (label_anchor +/- half the text
## width, horizontally) stays inside Rect2(Vector2.ZERO, size).
##
## `label_margin` / `label_text_width` were `const LABEL_MARGIN` /
## `LABEL_TEXT_WIDTH` when this file was written; they are now inspector
## knobs, so read them off the instance rather than the class.


func test_label_anchors_stay_within_control_rect() -> void:
	var radar := AttributeRadar.new()
	radar.size = Vector2(120, 120)
	add_child(radar)
	autofree(radar)
	await get_tree().process_frame

	var rect := Rect2(Vector2.ZERO, radar.size)
	var n := radar.axes.size()
	for i in n:
		var anchor: Vector2 = radar._label_anchor(i)
		# Mirror _draw()'s draw_string offset/width so this test reflects the
		# actual drawn text box, not just the raw anchor point.
		var half_width: float = radar.label_text_width * 0.5
		var box_left := anchor.x - half_width
		var box_right := anchor.x + half_width
		assert_true(rect.has_point(anchor),
			"axis %d label anchor %s must lie within control rect %s" % [i, anchor, rect])
		assert_true(box_left >= 0.0 and box_right <= radar.size.x,
			"axis %d label text box [%s, %s] must stay within control width %s" % [i, box_left, box_right, radar.size.x])


func test_label_radius_stays_inside_plot_radius_plus_gap() -> void:
	# _get_radius() (the plotted ring/dots/polygon radius) must not grow into
	# the space reserved for labels -- otherwise the plot itself would push
	# past the label ring and defeat the margin.
	var radar := AttributeRadar.new()
	radar.size = Vector2(120, 120)
	add_child(radar)
	autofree(radar)
	await get_tree().process_frame

	assert_true(radar._get_radius() <= radar._get_label_radius(),
		"plotted radius must not exceed the label ring radius")


func test_small_control_size_does_not_produce_negative_radius() -> void:
	# Guard against the margin math going negative on a tiny Control --
	# _get_radius()/_get_label_radius() should clamp, not go negative.
	var radar := AttributeRadar.new()
	radar.size = Vector2(20, 20)
	add_child(radar)
	autofree(radar)
	await get_tree().process_frame

	assert_true(radar._get_radius() >= 0.0)
	assert_true(radar._get_label_radius() >= 0.0)


func test_configure_replaces_axes_and_resets_values() -> void:
	# #241: configure() swaps the AxisSpec set (label + color) in one call and
	# zeroes the plotted values, replacing the old parallel-array poking.
	var radar := AttributeRadar.new()
	add_child(radar)
	autofree(radar)

	radar.configure([AxisSpec.new("A", Color.RED), AxisSpec.new("B", Color.BLUE), AxisSpec.new("C", Color.GREEN)])
	assert_eq(radar.axes.size(), 3, "configure() should set the axis count")
	assert_eq(radar.axes[1].label, "B")
	assert_eq(radar.axes[2].color, Color.GREEN)

	radar.set_value(1, 42.0)
	assert_almost_eq(radar._values[1], 42.0, 0.001, "set_value() should update the plotted value")

	# Re-configuring with the same count still resets stale values to zero.
	radar.configure([AxisSpec.new("X", Color.WHITE), AxisSpec.new("Y", Color.WHITE), AxisSpec.new("Z", Color.WHITE)])
	assert_almost_eq(radar._values[1], 0.0, 0.001, "configure() should reset plotted values")


func test_set_value_ignores_out_of_range_index() -> void:
	var radar := AttributeRadar.new()
	add_child(radar)
	autofree(radar)

	radar.configure([AxisSpec.new("A", Color.RED)])
	radar.set_value(5, 10.0)   # out of range — must be a no-op, not a crash
	radar.set_value(-1, 10.0)
	assert_eq(radar._values.size(), 1)
