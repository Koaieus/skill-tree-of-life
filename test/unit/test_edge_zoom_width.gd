extends GutTest

## #399 — Edge.width is authored in SCREEN pixels; the Line2D's actual
## world-space width must hold constant on-screen coverage across camera
## zoom, driven by Events.camera_zoom_changed rather than per-frame polling.

const _EDGE_SCENE := preload("res://graph/edge.tscn")


func test_line_width_scales_inversely_with_zoom() -> void:
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	await get_tree().process_frame

	edge.width = 2.5
	Events.camera_zoom_changed.emit(0.5)

	assert_almost_eq(edge.line_2d.width, 2.5 / 0.5, 0.0001)


func test_sensed_width_scale_still_composes_with_zoom() -> void:
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	await get_tree().process_frame

	edge.width = 2.5
	edge.sensed = true
	Events.camera_zoom_changed.emit(0.5)

	var expected := (2.5 / 0.5) * edge.sensed_width_scale
	assert_almost_eq(edge.line_2d.width, expected, 0.0001)


func test_zoom_change_does_not_touch_gradient() -> void:
	var edge := _EDGE_SCENE.instantiate() as Edge
	add_child_autofree(edge)
	await get_tree().process_frame

	var grad_before := edge.line_2d.gradient
	Events.camera_zoom_changed.emit(0.25)

	assert_same(edge.line_2d.gradient, grad_before, "a zoom-only change must not rebuild the Gradient")
