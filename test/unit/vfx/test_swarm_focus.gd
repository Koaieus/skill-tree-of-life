extends GutTest

## SwarmFocus (#1042): the damage-weighted COM of live projectiles, projected
## onto the wave's launch → landing segment. Pure — `project` takes points and
## weights and answers a position, so nothing here needs a frame.

var _focus: SwarmFocus


func before_each() -> void:
	_focus = SwarmFocus.new()
	add_child_autofree(_focus)
	_focus.begin_wave(Vector2(100, 0), Vector2(1100, 0))


func test_com_projects_onto_the_segment_at_the_weight_mean() -> void:
	# Weighted mean x = (200·1 + 600·3 + 1000·0) / 4 = 500 → 400 along a
	# 1000-px segment from x=100.
	var points := PackedVector2Array([Vector2(200, 0), Vector2(600, 0), Vector2(1000, 0)])
	var weights := PackedFloat32Array([1.0, 3.0, 0.0001])
	var at := _focus.project(points, weights)
	assert_almost_eq(at.x, 500.0, 0.1, "the weight-mean's scalar projection")
	assert_almost_eq(at.y, 0.0, 0.0001, "…on the segment")


func test_perpendicular_lift_does_not_move_the_marker() -> void:
	var flat := PackedVector2Array([Vector2(300, 0), Vector2(700, 0)])
	var lifted := PackedVector2Array([Vector2(300, -250), Vector2(700, 90)])
	var weights := PackedFloat32Array([2.0, 2.0])
	var a := _focus.project(flat, weights)
	var b := _focus.project(lifted, weights)
	assert_almost_eq(a, b, Vector2(0.0001, 0.0001),
			"the arc's lift is discarded — only progress along from→to counts")
	assert_almost_eq(a.x, 500.0, 0.0001)


func test_no_live_points_holds_the_last_position() -> void:
	_focus.global_position = Vector2(640, 0)
	var at := _focus.project(PackedVector2Array(), PackedFloat32Array())
	assert_eq(at, Vector2(640, 0), "an empty point set leaves the marker where it was")


func test_zero_weights_fall_back_to_the_status_floor() -> void:
	# All-zero weights weigh STATUS_FLOOR each → a plain mean, never NaN.
	var points := PackedVector2Array([Vector2(200, 0), Vector2(800, 0)])
	var at := _focus.project(points, PackedFloat32Array([0.0, 0.0]))
	assert_almost_eq(at.x, 500.0, 0.0001, "plain mean of the two")
	# A zero next to a real weight weighs the floor, not nothing.
	var mixed := _focus.project(points, PackedFloat32Array([0.0, SwarmFocus.STATUS_FLOOR]))
	assert_almost_eq(mixed.x, 500.0, 0.0001, "floor == the other's weight → the midpoint")


func test_the_projection_is_clamped_to_the_segment() -> void:
	var beyond := _focus.project(PackedVector2Array([Vector2(5000, 0)]), PackedFloat32Array([1.0]))
	assert_almost_eq(beyond, Vector2(1100, 0), Vector2(0.0001, 0.0001), "never past `to`")
	var before := _focus.project(PackedVector2Array([Vector2(-5000, 0)]), PackedFloat32Array([1.0]))
	assert_almost_eq(before, Vector2(100, 0), Vector2(0.0001, 0.0001), "never before `from`")


func test_begin_wave_parks_the_marker_at_from() -> void:
	_focus.begin_wave(Vector2(-30, 40), Vector2(900, 40))
	assert_eq(_focus.global_position, Vector2(-30, 40),
			"during the wind-up the marker sits at the firing centroid")
