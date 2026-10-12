extends GutTest
## AspectWheel geometry and signals — angles and radii off the node's own
## knobs, never pixels and never the knob defaults.

const _SIZE := Vector2(256, 256)

var _wheel: AspectWheel


func before_each() -> void:
	_wheel = AspectWheel.new()
	_wheel.size = _SIZE
	add_child_autofree(_wheel)


func _entries(n: int) -> Array[AspectWheelEntry]:
	var out: Array[AspectWheelEntry] = []
	for i in n:
		var identity := Identity.new()
		identity.id = StringName("aspect_%d" % i)
		identity.noun = "Aspect %d" % i
		identity.tint = Color.from_hsv(float(i) / maxf(1.0, n), 0.7, 0.9)
		out.append(AspectWheelEntry.new(identity.id, identity, i + 1))
	return out


## A point at `deg` clockwise from 12 o'clock, `r` px from the centre.
func _point(deg: float, r: float) -> Vector2:
	var a := deg_to_rad(deg) - PI / 2.0
	return _SIZE * 0.5 + Vector2(cos(a), sin(a)) * r


func _mid_point(i: int) -> Vector2:
	var span := _wheel.wedge_span(i)
	return _point((span.x + span.y) * 0.5, (_wheel.inner_radius_px + _wheel.radius_px) * 0.5)


func _assert_spans(n: int) -> void:
	var entries := _entries(n)
	_wheel.bind(entries)
	var step := 360.0 / n
	for i in n:
		var span := _wheel.wedge_span(i)
		assert_almost_eq(span.x, i * step + _wheel.wedge_gap_deg * 0.5, 0.001, "N=%d wedge %d start" % [n, i])
		assert_almost_eq(span.y, (i + 1) * step - _wheel.wedge_gap_deg * 0.5, 0.001, "N=%d wedge %d end" % [n, i])
		assert_eq(_wheel.wedge_at(_mid_point(i)), entries[i].id, "N=%d wedge %d hit" % [n, i])
	assert_eq(_wheel.wedge_at(_SIZE * 0.5), &"", "N=%d centre is the hub" % n)
	assert_eq(_wheel.wedge_at(_point(_wheel.wedge_span(0).x + 0.1, _wheel.inner_radius_px * 0.5)), &"", "N=%d inside hub" % n)
	assert_eq(_wheel.wedge_at(_point(_wheel.wedge_span(0).x + 0.1, _wheel.radius_px + 2.0)), &"", "N=%d outside radius" % n)
	# The gap straddling 12 o'clock belongs to no wedge.
	assert_eq(_wheel.wedge_at(_point(0.0, (_wheel.inner_radius_px + _wheel.radius_px) * 0.5)), &"", "N=%d seam gap" % n)


func test_spans_and_hits_n1() -> void:
	_assert_spans(1)


func test_spans_and_hits_n2() -> void:
	_assert_spans(2)


func test_spans_and_hits_n12() -> void:
	_assert_spans(12)


func test_fill_radius_scales_with_value_and_keeps_a_floor() -> void:
	var entries: Array[AspectWheelEntry] = []
	for v in [1, 2, 5, 10, 25, 50, 100]:
		entries.append(AspectWheelEntry.new(StringName("v%d" % v), null, v))
	_wheel.bind(entries)
	var previous := -INF
	for i in entries.size():
		var r := _wheel.fill_radius(i)
		assert_gt(r, previous, "fill grows with value (%d)" % entries[i].value)
		assert_true(r >= _wheel.min_fill * _wheel.radius_px, "fill %f at least min_fill × radius" % r)
		assert_true(r >= _wheel.inner_radius_px, "fill %f clears the hub" % r)
		assert_true(r <= _wheel.radius_px + 0.001, "fill %f within radius" % r)
		previous = r
	assert_almost_eq(_wheel.fill_radius(entries.size() - 1), _wheel.radius_px, 0.001, "max value fills the wedge")


func test_fill_floor_holds_when_min_fill_is_tuned() -> void:
	_wheel.min_fill = 0.4
	var entries: Array[AspectWheelEntry] = [AspectWheelEntry.new(&"lo", null, 1), AspectWheelEntry.new(&"hi", null, 1000)]
	_wheel.bind(entries)
	assert_true(_wheel.fill_radius(0) >= _wheel.min_fill * _wheel.radius_px)


func _click(button: MouseButton, at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = at
	_wheel._gui_input(ev)


func test_picked_fires_for_pickable_never_for_disabled() -> void:
	var entries := _entries(4)
	entries[1].disabled_reason = "Not enough"
	entries[2].checked = true
	_wheel.bind(entries)
	watch_signals(_wheel)
	_click(MOUSE_BUTTON_LEFT, _mid_point(1))
	assert_signal_not_emitted(_wheel, "picked")
	assert_signal_not_emitted(_wheel, "dismissed")
	_click(MOUSE_BUTTON_LEFT, _mid_point(2))
	assert_signal_emitted_with_parameters(_wheel, "picked", [entries[2].id])
	_click(MOUSE_BUTTON_LEFT, _mid_point(0))
	assert_signal_emitted_with_parameters(_wheel, "picked", [entries[0].id])
	assert_signal_emit_count(_wheel, "picked", 2)


func test_hover_reports_id_then_empty_on_leave() -> void:
	var entries := _entries(3)
	_wheel.bind(entries)
	watch_signals(_wheel)
	var motion := InputEventMouseMotion.new()
	motion.position = _mid_point(1)
	_wheel._gui_input(motion)
	assert_signal_emitted_with_parameters(_wheel, "hovered", [entries[1].id])
	_wheel._gui_input(motion)
	assert_signal_emit_count(_wheel, "hovered", 1, "hover emits on change only")
	_wheel.mouse_exited.emit()
	assert_signal_emitted_with_parameters(_wheel, "hovered", [&""])


func test_right_click_dismisses() -> void:
	_wheel.bind(_entries(3))
	watch_signals(_wheel)
	_click(MOUSE_BUTTON_RIGHT, _mid_point(0))
	assert_signal_emitted(_wheel, "dismissed")
	assert_signal_not_emitted(_wheel, "picked")


func test_ui_cancel_dismisses() -> void:
	_wheel.bind(_entries(3))
	watch_signals(_wheel)
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	_wheel._unhandled_input(ev)
	assert_signal_emitted(_wheel, "dismissed")
