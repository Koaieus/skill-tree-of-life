extends GutTest

## [SendBar] maps a click to an amount by its fraction FROM THE BOTTOM (the fill
## rises from the bottom), scroll nudges by one, all clamped to 0..stock; its
## border thirds light monotonically in stock across [code]border_decades[/code].

const _SCENE := preload("res://ui/hud/command_tray/bodies/send_bar.tscn")
const _H := 100.0


func _bar(stock: int, value: int = 0) -> SendBar:
	var bar: SendBar = _SCENE.instantiate()
	add_child_autofree(bar)
	bar.size = Vector2(20.0, _H)
	bar.stock = stock
	bar.value = value
	return bar


func _click_at(bar: SendBar, f_from_bottom: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(10.0, (1.0 - f_from_bottom) * _H)
	bar._gui_input(ev)


func _scroll(bar: SendBar, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = Vector2(10.0, _H * 0.5)
	bar._gui_input(ev)


func test_click_at_fraction_from_bottom_requests_that_share_of_stock() -> void:
	for f in [0.0, 0.25, 0.5, 0.73, 1.0]:
		var stock := 37
		var bar := _bar(stock)
		watch_signals(bar)
		_click_at(bar, f)
		assert_signal_emitted_with_parameters(bar, "value_requested", [roundi(f * stock)])


func test_drag_with_the_button_held_requests_too() -> void:
	var bar := _bar(20)
	watch_signals(bar)
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = Vector2(10.0, _H * 0.75)
	bar._gui_input(ev)
	assert_signal_emitted_with_parameters(bar, "value_requested", [5])


func test_scroll_nudges_by_one_clamped_to_stock() -> void:
	var bar := _bar(10, 4)
	watch_signals(bar)
	_scroll(bar, true)
	assert_signal_emitted_with_parameters(bar, "value_requested", [5])
	var top := _bar(10, 10)
	watch_signals(top)
	_scroll(top, true)
	assert_signal_emitted_with_parameters(top, "value_requested", [10])
	var bottom := _bar(10, 0)
	watch_signals(bottom)
	_scroll(bottom, false)
	assert_signal_emitted_with_parameters(bottom, "value_requested", [0])


func test_lit_thirds_monotone_in_stock_and_dark_at_zero() -> void:
	for decades in [PackedInt32Array([1, 10, 100]), PackedInt32Array([1, 5, 50]), PackedInt32Array([2, 20])]:
		assert_eq(SendBar.lit_thirds(0, decades), 0, "nothing lit at 0 for %s" % decades)
		var prev := 0
		var seen_max := 0
		for stock in range(0, 1000):
			var lit := SendBar.lit_thirds(stock, decades)
			if lit < prev:
				fail_test("not monotone at %d for %s" % [stock, decades])
				return
			prev = lit
			seen_max = maxi(seen_max, lit)
		assert_eq(SendBar.lit_thirds(decades[0], decades), 1, "the first bound lights one third")
		assert_eq(seen_max, decades.size(), "every third reached for %s" % decades)
