extends GutTest

## #894: a tracking follow is a rubber band — a critically damped spring on the
## camera, never a per-frame re-aim. Easing is not assertable in pixels, so
## these pin the spring's SHAPE: momentum from rest, no overshoot, convergence.

const DT := 1.0 / 60.0

var _cam: GraphCamera


func before_each() -> void:
	_cam = GraphCamera.new()
	add_child_autofree(_cam)
	_cam.limit_left = -100000
	_cam.limit_right = 100000
	_cam.limit_top = -100000
	_cam.limit_bottom = 100000
	_cam.global_position = Vector2.ZERO
	_cam.begin_directed_follow(Vector2.ZERO, 1.0, 0.0)


func test_a_target_jump_does_not_arrive_in_one_frame() -> void:
	_cam.set_follow_target(Vector2(1000, 0))
	_cam._follow(DT)
	assert_gt(_cam.global_position.x, 0.0, "it started moving")
	assert_lt(_cam.global_position.x, 1000.0, "but a band lags, it never welds")


func test_the_band_has_momentum_it_accelerates_out_of_rest() -> void:
	# The discriminator against the old first-order lerp, whose FIRST frame is
	# always its biggest step: a spring starts slow and picks up speed.
	_cam.set_follow_target(Vector2(1000, 0))
	_cam._follow(DT)
	var first := _cam.global_position.x
	_cam._follow(DT)
	var second := _cam.global_position.x - first
	assert_gt(second, first, "frame two covers more ground than frame one")


func test_the_band_never_overshoots_and_does_arrive() -> void:
	_cam.set_follow_target(Vector2(1000, 0))
	for i in 600:
		_cam._follow(DT)
		assert_lt(_cam.global_position.x, 1000.0 + 0.001,
				"critically damped: never past the target")
		if _cam.global_position.x >= 999.0:
			break
	assert_almost_eq(_cam.global_position.x, 1000.0, 1.0, "settles within ten seconds")
