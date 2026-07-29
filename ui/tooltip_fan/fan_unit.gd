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
## Since #303, FanUnit owns no Tween of its own — it sequences two
## self-animating components, per `.claude/rules/tooltip-fan.md`'s three-tier
## composition model: [FanTrace] and [FanPanel] each animate themselves
## (`play_in()` / `play_out() -> Tween`, readable `progress`); FanUnit just
## awaits one, then the other, in the sequential order decision 4 settled.

enum State { HIDDEN, IN, LOOP, OUT }

## Fires on every state transition, including the two "settled" endpoints
## (LOOP after IN, HIDDEN after OUT).
signal state_changed(new_state: State)

## Where along the panel edge the trace lands, 0 → 1 in reading order
## (top→bottom on a vertical edge, left→right on a horizontal one). 0.5 is the
## edge centre; 0 and 1 are its corners.
##
## WHICH edge is derived by [FanAnchor] — that's what keeps the arrival leg
## perpendicular to the panel border, never running alongside it. This is the
## one authored degree of freedom on top of that.
@export_range(0.0, 1.0, 0.01) var anchor_slide := 0.5

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

## Bumped by every public entry point ([method play_in] / [method play_out] /
## [method enter_hidden]). An `await` that resumes after a newer sequence has
## already begun checks the generation it started under and bails — without
## this, a fast hover→unhover leaves the IN sequence's pending continuation
## alive, and it unfurls the panel back in *after* OUT started.
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

## Starts the sequential IN sequence: trace draws in, tip arrives, THEN the
## panel unfurls, then settles into LOOP. Awaitable — the coordinator (#226)
## applies its own per-index stagger delay before calling this.
func play_in() -> void:
	_generation += 1
	var gen := _generation
	_set_state(State.IN)
	visible = true
	await _trace.play_in().finished
	if gen != _generation:
		return
	await _panel.play_in().finished
	if gen != _generation:
		return
	_set_state(State.LOOP)


# --- OUT: LOOP -> OUT -> HIDDEN ------------------------------------------------

## Starts the sequential OUT sequence: the reverse read — panel fades, THEN
## the trace erases — settling back into HIDDEN. Awaitable.
func play_out() -> void:
	_generation += 1
	var gen := _generation
	_set_state(State.OUT)
	await _panel.play_out().finished
	if gen != _generation:
		return
	await _trace.play_out().finished
	if gen != _generation:
		return
	visible = false
	_set_state(State.HIDDEN)


# --- HIDDEN: forced immediate reset -------------------------------------------

## Forces the machine straight to HIDDEN with no animation: invisible and
## inactive. Parks both children at their zero-reveal state.
func enter_hidden() -> void:
	_generation += 1
	_trace.progress = 0.0
	_panel.progress = 0.0
	visible = false
	_set_state(State.HIDDEN)


# --- internals -----------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)
