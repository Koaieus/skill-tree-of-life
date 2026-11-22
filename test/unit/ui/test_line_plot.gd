extends GutTest

## LinePlot's pure scaling: a shared y-domain that always holds 0, a shared
## x-domain across series, and nothing to draw for short series.

const RECT := Rect2(10, 20, 100, 50)


func _series(arrays: Array) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for a in arrays:
		out.append(PackedFloat32Array(a))
	return out


func test_range_includes_zero() -> void:
	assert_eq(LinePlot.value_range(_series([[3, 5, 4]])), Vector2(0, 5))
	assert_eq(LinePlot.value_range(_series([[-2, -6]])), Vector2(-6, 0))


func test_range_spans_every_series() -> void:
	assert_eq(LinePlot.value_range(_series([[1, 2], [-3, 7]])), Vector2(-3, 7))


func test_flat_range_is_widened() -> void:
	var r := LinePlot.value_range(_series([[0, 0, 0]]))
	assert_true(r.y > r.x, "a flat series still has a non-zero span")


func test_short_series_ignored_by_range() -> void:
	assert_eq(LinePlot.value_range(_series([[100], [1, 2]])), Vector2(0, 2))


func test_y_inverted_into_rect() -> void:
	assert_almost_eq(LinePlot.y_of(5.0, RECT, 0.0, 5.0), RECT.position.y, 0.001)
	assert_almost_eq(LinePlot.y_of(0.0, RECT, 0.0, 5.0), RECT.end.y, 0.001)


func test_points_share_x_domain() -> void:
	var count := LinePlot.x_count(_series([[1, 2, 3, 4, 5], [1, 2, 3]]))
	assert_eq(count, 5)
	var pts := LinePlot.to_points(PackedFloat32Array([1, 2, 3]), RECT, 0.0, 4.0, count)
	assert_eq(pts.size(), 3)
	assert_almost_eq(pts[0].x, RECT.position.x, 0.001)
	assert_almost_eq(pts[2].x, RECT.position.x + RECT.size.x * 0.5, 0.001)


func test_short_series_has_no_points() -> void:
	assert_true(LinePlot.to_points(PackedFloat32Array(), RECT, 0.0, 1.0, 5).is_empty())
	assert_true(LinePlot.to_points(PackedFloat32Array([3]), RECT, 0.0, 1.0, 5).is_empty())


func test_set_series_empty_and_single_point_do_not_error() -> void:
	var plot: LinePlot = add_child_autofree(preload("res://ui/widgets/line_plot.tscn").instantiate())
	plot.size = Vector2(120, 40)
	plot.set_series(_series([]), PackedColorArray())
	plot.set_series(_series([[2]]), PackedColorArray([Color.RED]))
	plot.set_series(_series([[1, 2], [3, 4]]), PackedColorArray([Color.RED]))
	await get_tree().process_frame
	assert_true(is_instance_valid(plot))
