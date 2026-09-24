extends GutTest

## [TweenClock] — the tween consumer's step-by-hand door. ##
## Contract, proven by the 2026-09-23 spike (a paused Tween on an in-tree node
## steps property, interval and callback in order through `custom_step`, and
## two real frames later nothing has moved):
##   * manual=false → `tween(host)` is a running tween, indistinguishable from
##     `host.create_tween()`.
##   * manual=true → the tween is paused at birth; `advance(d)` steps it by d.
##   * `advance` fires `tween_callback` at the exact stepped instant, once.
##   * finished / killed tweens are pruned; `advance` on an empty clock is free.
##   * `kill_all` leaves no live tween.


var _host: Node2D
var _clock: TweenClock


func before_each() -> void:
	_host = Node2D.new()
	add_child_autofree(_host)
	_clock = TweenClock.new()


func test_manual_false_hands_out_a_running_tween() -> void:
	var tw := _clock.tween(_host)
	assert_not_null(tw, "tween() hands out a Tween")
	tw.tween_property(_host, ^"position:x", 10.0, 0.5)
	assert_true(tw.is_valid(), "it is live")
	assert_true(tw.is_running(), "and running on the real clock, as a bare create_tween() is")


func test_manual_true_creates_the_tween_paused_and_two_real_frames_move_nothing() -> void:
	_clock.manual = true
	var tw := _clock.tween(_host)
	assert_not_null(tw)
	tw.tween_property(_host, ^"position:x", 10.0, 0.01)
	assert_false(tw.is_running(), "paused at birth")
	await wait_frames(2)
	assert_eq(_host.position.x, 0.0, "two real frames later nothing has moved")
	_clock.advance(0.005)
	assert_almost_eq(_host.position.x, 5.0, 0.01, "advance is what moves it")


func test_advance_steps_property_then_interval_then_callback_in_order() -> void:
	_clock.manual = true
	var seen: Array[float] = []
	var tw := _clock.tween(_host)
	tw.tween_property(_host, ^"position:x", 10.0, 1.0)
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: seen.append(_host.position.x))
	_clock.advance(1.0)
	assert_almost_eq(_host.position.x, 10.0, 0.001, "the property lands at its own duration")
	assert_eq(seen.size(), 0, "the interval still holds the callback back")
	_clock.advance(0.4)
	assert_eq(seen.size(), 0, "still inside the interval")
	_clock.advance(0.11)
	assert_eq(seen, [10.0] as Array[float], "the callback fires at the stepped instant, after the property")
	_clock.advance(1.0)
	assert_eq(seen.size(), 1, "and only once")


func test_a_finished_tween_is_pruned_and_a_killed_one_is_skipped() -> void:
	_clock.manual = true
	var fires: Array[int] = []
	var done := _clock.tween(_host)
	done.tween_interval(0.1)
	var killed := _clock.tween(_host)
	killed.tween_interval(0.1)
	killed.tween_callback(func() -> void: fires.append(1))
	assert_eq(_clock.live_count(), 2, "both tracked")
	killed.kill()
	_clock.advance(0.2)
	assert_eq(fires.size(), 0, "a killed tween is skipped, its callback never runs")
	assert_eq(_clock.live_count(), 0, "the finished and the killed are both pruned")
	_clock.advance(0.2)
	assert_eq(_clock.live_count(), 0, "advance on an empty clock is free")


func test_tween_prunes_dead_entries_even_without_advance() -> void:
	_clock.manual = true
	for i in 3:
		_clock.tween(_host).tween_interval(0.1)
		_clock.kill_all()
	_clock.tween(_host).tween_interval(0.1)
	assert_eq(_clock.live_count(), 1, "production never calls advance, so tween() prunes")


func test_a_tween_born_in_a_callback_first_moves_on_the_next_advance() -> void:
	_clock.manual = true
	var tw := _clock.tween(_host)
	tw.tween_callback(func() -> void:
		_clock.tween(_host).tween_property(_host, ^"position:x", 10.0, 1.0))
	_clock.advance(0.5)
	assert_eq(_host.position.x, 0.0, "a tween born mid-advance is not stepped by it")
	_clock.advance(0.5)
	assert_almost_eq(_host.position.x, 5.0, 0.001, "it moves from the next advance")


func test_a_killed_tween_does_not_leak_through_its_finished_connection() -> void:
	_clock.manual = true
	var tw := _clock.tween(_host)
	tw.tween_interval(1.0)
	var tw_ref: WeakRef = weakref(tw)
	var clock_ref: WeakRef = weakref(_clock)
	tw.kill()
	tw = null
	_clock = null
	await wait_seconds(0.2)
	assert_null(tw_ref.get_ref(), "the killed tween is freed, not held by its own finished connection")
	assert_null(clock_ref.get_ref(), "the clock is freed too, not held in the cycle")


func test_kill_all_leaves_nothing_live() -> void:
	_clock.manual = true
	var a := _clock.tween(_host)
	a.tween_property(_host, ^"position:x", 10.0, 1.0)
	var b := _clock.tween(_host)
	b.tween_interval(1.0)
	_clock.kill_all()
	assert_false(a.is_valid(), "first killed")
	assert_false(b.is_valid(), "second killed")
	assert_eq(_clock.live_count(), 0, "nothing live")
	_clock.advance(1.0)
	assert_eq(_host.position.x, 0.0, "and nothing moves")
