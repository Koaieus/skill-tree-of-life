extends GutTest

## GraphCamera.reveal(rect, policy): NUDGE pans by the minimal delta that fits
## the rect (inset by reveal_margin_px) inside the view, CENTRE centres on it;
## both respect the pan limits and always settle via `reveal_settled`.

const WAIT_S := 0.5

var _cam: GraphCamera


func before_each() -> void:
	_cam = GraphCamera.new()
	add_child_autofree(_cam)
	_cam.limit_left = -100000
	_cam.limit_right = 100000
	_cam.limit_top = -100000
	_cam.limit_bottom = 100000
	_cam.global_position = Vector2.ZERO
	_cam.reveal_duration = 0.0


func _inset_view() -> Rect2:
	return _cam.view_rect().grow(-_cam.reveal_margin_px / _cam.zoom.x)


func test_nudge_on_a_rect_already_in_view_is_a_same_frame_no_op() -> void:
	_cam.reveal_duration = 0.12
	var fired_on: Array = [-1]
	_cam.reveal_settled.connect(func() -> void: fired_on[0] = Engine.get_process_frames())
	var frame := Engine.get_process_frames()
	var sig := _cam.reveal(Rect2(-10, -10, 20, 20), GraphCamera.RevealPolicy.NUDGE)
	var ok: bool = await wait_for_signal(sig, WAIT_S)
	assert_true(ok, "reveal_settled fired")
	assert_eq(fired_on[0], frame, "within the same frame")
	assert_eq(_cam.global_position, Vector2.ZERO, "position unchanged")


func test_nudge_off_the_right_edge_pans_minimally_into_the_inset() -> void:
	var view := _cam.view_rect()
	var rect := Rect2(view.end.x - 20.0, -10.0, 100.0, 20.0)
	var ok: bool = await wait_for_signal(
			_cam.reveal(rect, GraphCamera.RevealPolicy.NUDGE), WAIT_S)
	assert_true(ok, "reveal_settled fired")
	var inset := _inset_view()
	assert_true(inset.encloses(rect), "rect ends inside the inset view")
	assert_almost_eq(rect.end.x, inset.end.x, 1.0, "right edge sits at the inset edge")
	assert_almost_eq(_cam.global_position.y, 0.0, 0.001, "no pan on the fitting axis")


func test_centre_centres_on_the_rect() -> void:
	var rect := Rect2(300.0, -500.0, 40.0, 60.0)
	var ok: bool = await wait_for_signal(
			_cam.reveal(rect, GraphCamera.RevealPolicy.CENTRE), WAIT_S)
	assert_true(ok, "reveal_settled fired")
	assert_almost_eq(_cam.global_position.x, rect.get_center().x, 0.5)
	assert_almost_eq(_cam.global_position.y, rect.get_center().y, 0.5)


func test_a_rect_past_the_limits_ends_at_the_clamped_position() -> void:
	_cam.limit_left = -2000
	_cam.limit_right = 2000
	_cam.limit_top = -2000
	_cam.limit_bottom = 2000
	var half := _cam.view_rect().size * 0.5
	var rect := Rect2(5000.0, 5000.0, 50.0, 50.0)
	var ok: bool = await wait_for_signal(
			_cam.reveal(rect, GraphCamera.RevealPolicy.NUDGE), WAIT_S)
	assert_true(ok, "reveal_settled still fires")
	assert_almost_eq(_cam.global_position.x, 2000.0 - half.x, 0.5)
	assert_almost_eq(_cam.global_position.y, 2000.0 - half.y, 0.5)


func test_an_eased_reveal_settles_on_its_target() -> void:
	_cam.reveal_duration = 0.05
	var rect := Rect2(1000.0, 0.0, 10.0, 10.0)
	var ok: bool = await wait_for_signal(
			_cam.reveal(rect, GraphCamera.RevealPolicy.CENTRE), WAIT_S)
	assert_true(ok, "reveal_settled fired after the ease")
	assert_almost_eq(_cam.global_position.x, rect.get_center().x, 0.5)


func test_manual_input_cancels_a_reveal_and_still_settles() -> void:
	_cam.reveal_duration = 0.3
	var sig := _cam.reveal(Rect2(5000.0, 0.0, 10.0, 10.0), GraphCamera.RevealPolicy.CENTRE)
	_cam.pan_to(Vector2(-50.0, 0.0))
	var ok: bool = await wait_for_signal(sig, WAIT_S)
	assert_true(ok, "a cancelled reveal still settles")
	assert_almost_eq(_cam.global_position.x, -50.0, 0.5, "the manual pan wins")


func test_a_newer_reveal_does_not_settle_early_for_its_caller() -> void:
	_cam.reveal_duration = 0.1
	_cam.reveal(Rect2(3000.0, 0.0, 10.0, 10.0), GraphCamera.RevealPolicy.CENTRE)
	var rect := Rect2(1000.0, 0.0, 10.0, 10.0)
	var ok: bool = await wait_for_signal(
			_cam.reveal(rect, GraphCamera.RevealPolicy.CENTRE), WAIT_S)
	assert_true(ok, "reveal_settled fired")
	assert_almost_eq(_cam.global_position.x, rect.get_center().x, 0.5,
			"the settle is the newer pan's, not the superseded one's")
