extends GutTest

## Tooltip V2 (#159, #224): FanUnit pairs a FanTrace with a FanPanel under a
## HIDDEN -> IN -> LOOP -> OUT -> HIDDEN state machine. Trace->panel ordering
## is sequential only (#215's rescope dropped the sync_in/sync_out enum): the
## trace draws in, its tip arrives, THEN the panel unfurls; OUT reverses that
## read (panel fades, then trace erases).
##
## Per the acceptance spec, these tests use immediate state checks by calling
## the private continuations directly (mirroring test_fan_trace.gd's
## `_on_draw_in_finished()` pattern) rather than awaiting real Tween durations.

const _SCENE := preload("res://ui/tooltip_fan/fan_unit.tscn")


func _make() -> FanUnit:
	var unit := _SCENE.instantiate() as FanUnit
	add_child(unit)
	autofree(unit)
	return unit


## Drives a unit from HIDDEN all the way to LOOP using immediate continuation
## calls (no real Tween waits). Also force-settles FanTrace's own real
## draw-in tween (kicked, but never awaited, by play_in()) so its
## `_is_animating` flag doesn't leak into later OUT-sequence assertions —
## mirrors test_fan_trace.gd's own `_on_draw_in_finished()` jump pattern.
func _advance_to_loop(unit: FanUnit) -> void:
	unit.play_in()
	unit._on_trace_drawn_in()
	if unit._trace._lifecycle_tween != null:
		unit._trace._lifecycle_tween.kill()
	unit._trace._on_draw_in_finished()
	unit._on_panel_unfurled()


# --- initial state -------------------------------------------------------------

func test_starts_hidden_and_invisible() -> void:
	var unit := _make()
	await get_tree().process_frame
	assert_eq(unit.state, FanUnit.State.HIDDEN)
	assert_false(unit.visible, "HIDDEN is invisible")


# --- IN: HIDDEN -> IN -> LOOP ---------------------------------------------------

func test_play_in_immediately_enters_in_state_and_becomes_visible() -> void:
	var unit := _make()
	await get_tree().process_frame
	unit.play_in()
	assert_eq(unit.state, FanUnit.State.IN)
	assert_true(unit.visible)


func test_play_in_does_not_start_the_panel_unfurl_yet() -> void:
	# Sequential ordering: right after play_in(), the trace is drawing but the
	# panel must still be at its pre-unfurl (invisible) reveal state.
	var unit := _make()
	await get_tree().process_frame
	unit.play_in()
	assert_almost_eq(unit._panel.modulate.a, 0.0, 0.001,
		"panel must not unfurl until the trace's tip arrives")


func test_trace_drawn_in_starts_panel_unfurl_while_still_in() -> void:
	var unit := _make()
	await get_tree().process_frame
	unit.play_in()
	unit._on_trace_drawn_in()
	assert_eq(unit.state, FanUnit.State.IN, "still IN while the panel unfurl runs")


func test_panel_unfurled_settles_into_loop() -> void:
	var unit := _make()
	await get_tree().process_frame
	_advance_to_loop(unit)
	assert_eq(unit.state, FanUnit.State.LOOP)


# --- OUT: LOOP -> OUT -> HIDDEN --------------------------------------------------

func test_play_out_immediately_enters_out_state() -> void:
	var unit := _make()
	await get_tree().process_frame
	_advance_to_loop(unit)
	unit.play_out()
	assert_eq(unit.state, FanUnit.State.OUT)


func test_play_out_does_not_start_the_trace_erase_yet() -> void:
	# Reverse-sequential ordering: right after play_out(), the panel is fading
	# but the trace must still be untouched (fully drawn, not erasing).
	var unit := _make()
	await get_tree().process_frame
	_advance_to_loop(unit)
	unit.play_out()
	assert_false(unit._trace._is_animating, "trace erase hasn't started until the panel fully fades")


func test_panel_faded_starts_trace_erase_while_still_out() -> void:
	var unit := _make()
	await get_tree().process_frame
	_advance_to_loop(unit)
	unit.play_out()
	unit._on_panel_faded()
	assert_eq(unit.state, FanUnit.State.OUT, "still OUT while the trace erases")
	assert_true(unit._trace._is_animating, "trace erase tween is now running")


func test_trace_erased_returns_to_hidden_and_invisible() -> void:
	var unit := _make()
	await get_tree().process_frame
	_advance_to_loop(unit)
	unit.play_out()
	unit._on_panel_faded()
	unit._on_trace_erased()
	assert_eq(unit.state, FanUnit.State.HIDDEN)
	assert_false(unit.visible)


# --- forced immediate reset ------------------------------------------------------

func test_enter_hidden_forces_state_regardless_of_current_state() -> void:
	var unit := _make()
	await get_tree().process_frame
	_advance_to_loop(unit)
	assert_eq(unit.state, FanUnit.State.LOOP)

	unit.enter_hidden()
	assert_eq(unit.state, FanUnit.State.HIDDEN)
	assert_false(unit.visible)
	assert_almost_eq(unit._trace.progress, 0.0, 0.001)
	assert_almost_eq(unit._panel.modulate.a, 0.0, 0.001)


# --- signal --------------------------------------------------------------------

func test_state_changed_emits_on_transition() -> void:
	var unit := _make()
	await get_tree().process_frame
	watch_signals(unit)
	unit.play_in()
	assert_signal_emitted_with_parameters(unit, "state_changed", [FanUnit.State.IN])


func test_state_changed_does_not_emit_for_a_no_op_transition() -> void:
	var unit := _make()
	await get_tree().process_frame
	unit.enter_hidden() # already HIDDEN from _ready()
	watch_signals(unit)
	unit.enter_hidden()
	assert_signal_not_emitted(unit, "state_changed")


# --- trace_idle forwarding -------------------------------------------------------

func test_trace_idle_export_forwards_to_the_trace() -> void:
	var unit := _make()
	await get_tree().process_frame
	unit.trace_idle = true
	assert_true(unit._trace.trace_idle)
