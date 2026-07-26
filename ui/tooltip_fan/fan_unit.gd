@tool
class_name FanUnit
extends Node2D
## Tooltip V2 (#159, #224) — one reusable trace+panel pair: pairs a
## [FanTrace] with a [FanPanel] under a single
## `HIDDEN → IN → LOOP → OUT → HIDDEN` state machine.
##
## Rescoped by #215: trace→panel ordering is SEQUENTIAL ONLY — the line draws
## in, the glowing tip arrives, THEN the panel unfurls at the tip. The old
## sequential/simultaneous/reverse `sync_in`/`sync_out` enum is dropped from
## scope; there is nothing to configure here.
##
## No per-unit stagger: the TooltipFan coordinator (#226) owns stagger by
## delaying its call to [method play_in] per index. This scene has no delay
## knob of its own.
##
## Each transition is driven by a Tween and is awaitable:
## `await fan_unit.play_in()` / `await fan_unit.play_out()`. Internally each
## public entry point is split from its continuation (`_on_trace_drawn_in`,
## `_on_panel_unfurled`, `_on_panel_faded`, `_on_trace_erased`) exactly like
## [FanTrace]'s own `_on_draw_in_finished` — a test can call a continuation
## directly to jump the state machine forward without waiting on real Tween
## durations.

enum State { HIDDEN, IN, LOOP, OUT }

## Fires on every state transition, including the two "settled" endpoints
## (LOOP after IN, HIDDEN after OUT).
signal state_changed(new_state: State)

@export_group("Motion")
## Duration of the panel's unfurl tween (fires once the trace's tip arrives).
@export var panel_unfurl_duration := 0.22
## Duration of the panel's fade-out tween (fires first in the OUT sequence).
@export var panel_fade_duration := 0.16
## Forwarded to [member FanTrace.trace_idle] — whether the settled trace tip
## keeps a soft idle pulse through LOOP. Panel idle motion is out of scope
## here (#234).
@export var trace_idle := false:
	set(value):
		trace_idle = value
		if _trace:
			_trace.trace_idle = value

## Current machine state. Read-only from outside — drive transitions through
## [method play_in] / [method play_out] / [method enter_hidden], never by
## assigning this directly.
var state: State = State.HIDDEN

@onready var _trace: FanTrace = %Trace
@onready var _panel: FanPanel = %Panel

## Drives the panel-only reveal (progress 0..1 / 1..0). FanTrace owns its own
## lifecycle tween internally; this is FanUnit's, per
## `.claude/rules/tooltip-fan.md` — FanPanel never owns a Tween itself, only
## `set_progress(t)` driven by an external clock.
var _unit_tween: Tween = null

## Bumped by every public entry point ([method play_in] / [method play_out] /
## [method enter_hidden]). A continuation that resumes after its `await` checks
## the generation it started under and bails if a newer sequence has since
## begun — without this, a fast hover→unhover leaves the IN sequence's pending
## continuation alive, and it unfurls the panel back in *after* OUT started.
## Continuations called directly (the test path) simply read the current
## generation and so never bail.
var _generation := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		# Author-time: leave whatever's on-scene visible so trace/panel
		# placement is witnessable while dragging, and write NOTHING to the
		# children — a @tool _ready that sets child properties dirties the
		# scene on every editor load (.claude/rules/godot-workflow.md).
		return
	_trace.trace_idle = trace_idle
	enter_hidden()


# --- IN: HIDDEN -> IN -> LOOP -------------------------------------------------

## Starts the sequential IN sequence: trace draws in, tip arrives, panel
## unfurls, then settles into LOOP. Awaitable — the coordinator (#226) applies
## its own per-index stagger delay before calling this.
func play_in() -> void:
	_generation += 1
	var gen := _generation
	_set_state(State.IN)
	visible = true
	var trace_tween := _trace.play_draw_in()
	await trace_tween.finished
	if gen != _generation:
		return
	_on_trace_drawn_in()


## Continuation of [method play_in] once the trace's tip has arrived. Starts
## the panel unfurl. Split out so a test can call it directly and skip
## waiting on the trace's real draw-in duration.
func _on_trace_drawn_in() -> void:
	var gen := _generation
	_kill_unit_tween()
	_unit_tween = create_tween()
	_unit_tween.tween_method(_panel.set_progress, 0.0, 1.0, panel_unfurl_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _unit_tween.finished
	if gen != _generation:
		return
	_on_panel_unfurled()


## Continuation of [method _on_trace_drawn_in] once the panel has finished
## unfurling. Settles the machine into LOOP.
func _on_panel_unfurled() -> void:
	_set_state(State.LOOP)


# --- OUT: LOOP -> OUT -> HIDDEN ------------------------------------------------

## Starts the sequential OUT sequence: the reverse read — panel fades, THEN
## the trace erases — settling back into HIDDEN. Awaitable.
func play_out() -> void:
	_generation += 1
	var gen := _generation
	_set_state(State.OUT)
	_kill_unit_tween()
	_unit_tween = create_tween()
	_unit_tween.tween_method(_panel.set_progress, 1.0, 0.0, panel_fade_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await _unit_tween.finished
	if gen != _generation:
		return
	_on_panel_faded()


## Continuation of [method play_out] once the panel has fully faded. Starts
## the trace erase. Split out so a test can call it directly and skip waiting
## on the panel's real fade duration.
func _on_panel_faded() -> void:
	var gen := _generation
	var trace_tween := _trace.play_erase()
	await trace_tween.finished
	if gen != _generation:
		return
	_on_trace_erased()


## Continuation of [method _on_panel_faded] once the trace has fully erased.
## Settles the machine into HIDDEN.
func _on_trace_erased() -> void:
	visible = false
	_set_state(State.HIDDEN)


# --- HIDDEN: forced immediate reset -------------------------------------------

## Forces the machine straight to HIDDEN with no animation: invisible and
## inactive. Kills any running unit tween; parks both children at their
## zero-reveal state.
func enter_hidden() -> void:
	_generation += 1
	_kill_unit_tween()
	_trace.progress = 0.0
	_panel.set_progress(0.0)
	visible = false
	_set_state(State.HIDDEN)


# --- internals -----------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)


func _kill_unit_tween() -> void:
	if _unit_tween != null and _unit_tween.is_valid():
		_unit_tween.kill()
	_unit_tween = null
