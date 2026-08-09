extends GutTest

## Tooltip V2 (#159, #224, #303): FanUnit pairs a FanTrace with a FanPanel under
## a HIDDEN -> IN -> LOOP -> OUT -> HIDDEN state machine. Trace->panel ordering
## is sequential only (#215's rescope dropped the sync_in/sync_out enum): the
## trace draws in, its tip arrives, THEN the panel unfurls; OUT reverses that
## read (panel fades, then trace erases).
##
## Since #303, FanUnit owns no Tween of its own — [method FanUnit.play_in] /
## [method FanUnit.play_out] just `await` each component's own `play_in()` /
## `play_out()` Tween in sequence. These tests force each component's own
## lifecycle tween to completion with `Tween.custom_step(1000.0)` (which fires
## `finished` synchronously, resuming FanUnit's awaiting coroutine inline)
## instead of waiting on real Tween durations or calling private
## continuations — there are none left to call.

const _SCENE := preload("res://ui/tooltip_fan/fan_unit.tscn")
const _TRACE_SCENE := preload("res://ui/tooltip_fan/fan_trace.tscn")
const _PANEL_SCENE := preload("res://ui/tooltip_fan/fan_panel.tscn")


## fan_unit.tscn (#380) is the inheritance base every concrete unit adds its
## own Panel onto — it ships with no baked Panel, so tests build one the same
## way a concrete unit scene does.
func _make() -> FanUnit:
	var unit := _SCENE.instantiate() as FanUnit
	var panel := _PANEL_SCENE.instantiate()
	panel.name = "Panel"
	panel.unique_name_in_owner = true
	unit.add_child(panel)
	panel.owner = unit
	add_child(unit)
	autofree(unit)
	return unit


## Drives a unit from HIDDEN all the way to LOOP by force-completing each
## component's own lifecycle tween in sequence (no real Tween waits).
func _advance_to_loop(unit: FanUnit) -> void:
	unit.play_in()
	unit._trace._lifecycle_tween.custom_step(1000.0)
	unit._panel._lifecycle_tween.custom_step(1000.0)


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


func test_trace_arriving_starts_panel_unfurl_while_still_in() -> void:
	var unit := _make()
	await get_tree().process_frame
	unit.play_in()
	unit._trace._lifecycle_tween.custom_step(1000.0) # trace's tip arrives
	assert_eq(unit.state, FanUnit.State.IN, "still IN while the panel unfurl runs")
	assert_not_null(unit._panel._lifecycle_tween, "panel's own unfurl tween has started")


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
	unit._panel._lifecycle_tween.custom_step(1000.0) # panel finishes fading
	assert_eq(unit.state, FanUnit.State.OUT, "still OUT while the trace erases")
	assert_true(unit._trace._is_animating, "trace erase tween is now running")


func test_trace_erased_returns_to_hidden_and_invisible() -> void:
	var unit := _make()
	await get_tree().process_frame
	_advance_to_loop(unit)
	unit.play_out()
	unit._panel._lifecycle_tween.custom_step(1000.0)
	unit._trace._lifecycle_tween.custom_step(1000.0)
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


# --- idle animation forwarding (#234) -------------------------------------------

func test_trace_idle_anim_export_forwards_to_the_trace() -> void:
	var unit := _make()
	await get_tree().process_frame
	var anim := FanAnimation.new()
	unit.trace_idle_anim = anim
	assert_same(unit._trace.idle_anim, anim, "the unit forwards its trace idle resource")


func test_panel_idle_anim_export_forwards_to_the_panel() -> void:
	var unit := _make()
	await get_tree().process_frame
	var anim := FanAnimation.new()
	unit.panel_idle_anim = anim
	assert_same(unit._panel.idle_anim, anim, "the unit forwards its panel idle resource")


func test_idle_exports_null_by_default() -> void:
	var unit := _make()
	await get_tree().process_frame
	assert_null(unit._trace.idle_anim, "idle is opt-in: nothing ships with an idle animation")
	assert_null(unit._panel.idle_anim, "idle is opt-in: nothing ships with an idle animation")


# --- shared component contract (#303) --------------------------------------------

## FanUnit's whole sequencing model depends on FanTrace and FanPanel answering
## to the exact same duck-typed surface: play_in()/play_out() -> Tween, plus a
## readable progress that settles at 1.0/0.0. Assert both components pass the
## same calls.
func test_trace_and_panel_share_identical_play_in_play_out_progress_surface() -> void:
	var trace := _TRACE_SCENE.instantiate()
	add_child(trace)
	autofree(trace)
	var panel := _PANEL_SCENE.instantiate()
	add_child(panel)
	autofree(panel)
	await get_tree().process_frame

	for component in [trace, panel]:
		var tw_in: Tween = component.play_in()
		assert_not_null(tw_in, "%s.play_in() returns a Tween" % component.get_class())
		tw_in.custom_step(1000.0)
		assert_almost_eq(component.progress, 1.0, 0.001,
			"%s.progress settles at 1.0 after play_in()" % component.get_class())

		var tw_out: Tween = component.play_out()
		assert_not_null(tw_out, "%s.play_out() returns a Tween" % component.get_class())
		tw_out.custom_step(1000.0)
		assert_almost_eq(component.progress, 0.0, 0.001,
			"%s.progress settles at 0.0 after play_out()" % component.get_class())
