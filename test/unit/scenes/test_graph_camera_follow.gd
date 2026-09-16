extends GutTest

## #894/#931: a tracking follow is a rubber band — a critically damped spring on
## the camera, never a per-frame re-aim. Easing is not assertable in pixels, so
## these pin the spring's SHAPE: momentum from rest, no overshoot, convergence.
## The camera POLLS a [Node2D] (#931) rather than being pushed a Vector2
## goalpost, so the fixture is a plain Node2D moved by hand between `_follow`
## calls.

const DT := 1.0 / 60.0

var _cam: GraphCamera
var _target: Node2D


func before_each() -> void:
	_cam = GraphCamera.new()
	add_child_autofree(_cam)
	_cam.limit_left = -100000
	_cam.limit_right = 100000
	_cam.limit_top = -100000
	_cam.limit_bottom = 100000
	_cam.global_position = Vector2.ZERO
	_target = Node2D.new()
	add_child_autofree(_target)
	_cam.begin_directed_follow(_target, 1.0, 0.0)


func test_a_target_jump_does_not_arrive_in_one_frame() -> void:
	_target.global_position = Vector2(1000, 0)
	_cam._follow(DT)
	assert_gt(_cam.global_position.x, 0.0, "it started moving")
	assert_lt(_cam.global_position.x, 1000.0, "but a band lags, it never welds")


func test_the_band_has_momentum_it_accelerates_out_of_rest() -> void:
	# The discriminator against the old first-order lerp, whose FIRST frame is
	# always its biggest step: a spring starts slow and picks up speed.
	_target.global_position = Vector2(1000, 0)
	_cam._follow(DT)
	var first := _cam.global_position.x
	_cam._follow(DT)
	var second := _cam.global_position.x - first
	assert_gt(second, first, "frame two covers more ground than frame one")


func test_the_band_never_overshoots_and_does_arrive() -> void:
	_target.global_position = Vector2(1000, 0)
	for i in 600:
		_cam._follow(DT)
		assert_lt(_cam.global_position.x, 1000.0 + 0.001,
				"critically damped: never past the target")
		if _cam.global_position.x >= 999.0:
			break
	assert_almost_eq(_cam.global_position.x, 1000.0, 1.0, "settles within ten seconds")


func test_rebind_follow_swaps_the_node_without_restarting_the_pan_or_zoom() -> void:
	# Acceptance 2: rebind while the pan tween is running leaves the tween
	# running and does not change zoom.
	_cam.begin_directed_follow(_target, 1.0, 5.0)
	assert_true(_cam.is_pan_tween_running(), "a real duration opens a tween")
	var other := Node2D.new()
	add_child_autofree(other)
	other.global_position = Vector2(500, 500)
	var zoom_before: float = _cam._target_zoom
	_cam.rebind_follow(other)
	assert_true(_cam.is_pan_tween_running(), "rebind does not touch the tween")
	assert_eq(_cam._target_zoom, zoom_before, "and never the zoom")


func test_freeing_the_followed_node_holds_the_spring_at_its_last_aim() -> void:
	# Acceptance 3: freeing the followed node mid-follow — no error, no jump —
	# the spring holds its LAST TARGET (frozen) and keeps converging on it,
	# rather than crashing on a freed reference or snapping to zero.
	var doomed := Node2D.new()
	add_child(doomed)
	_cam.rebind_follow(doomed)
	doomed.global_position = Vector2(1000, 0)
	_cam._follow(DT)
	assert_gt(_cam.global_position.x, 0.0, "it started moving toward the target")
	doomed.queue_free()
	await get_tree().process_frame
	assert_false(is_instance_valid(doomed), "sanity: the target really is gone")
	for i in 600:
		_cam._follow(DT)
	assert_almost_eq(_cam.global_position.x, 1000.0, 1.0,
			"still converges on the last-known target — no crash, no jump")
