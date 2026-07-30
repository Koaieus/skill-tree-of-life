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

## Which way this trace must ENTER its panel. `AUTO` (the default) forces
## nothing and leaves [FanAnchor] to derive the edge exactly as before.
##
## Naming an axis instead makes the arrival a constraint the geometry has to
## satisfy: the edge becomes the one facing the pin, and [FanAnchor.solve_route]
## solves the trunk length that guarantees the closing leg lands on that axis.
## Two payoffs beyond taste — the derived edge can't disagree with the drawn
## route (the 2-cycle is unreachable once the axis is given), and a panel sitting
## near 45° from its pin stops being ambiguous without being moved.
##
## Note that a forced axis makes [member FanTrace.bend_start] inert for this
## unit: the trunk is solved, not fractional. Steer it with [member trunk_length].
@export var arrival_axis: FanAnchor.Axis = FanAnchor.Axis.AUTO

## How far the trace runs along its trunk before breaking to 45°, in pixels.
## 0 (the default) keeps [member FanTrace.bend_start]'s fraction-of-the-span
## behaviour, so near panels get short trunks and far ones long trunks.
##
## Under an [member arrival_axis] this is a PREFERENCE WITHIN the constraint,
## not an override of it: a length that would land the arrival on the wrong axis
## is clamped to the nearest one that doesn't. Asking for a longer run up before
## the bend is always available; asking for one so short the line would come in
## vertically, while demanding a horizontal arrival, is not.
@export_range(0.0, 300.0, 1.0, "or_greater") var trunk_length := 0.0

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

## Whether this unit is part of the fan for the currently-hovered node — i.e.
## its panel had something to show at the last [method bind]. Owned by
## [TooltipFan], which writes it in the same pass that binds the panel, so the
## classification can never lag a frame behind the content (#314).
##
## Two readers, and they must agree: [TooltipFan] decides whether to play the
## unit in, and [FanAnchorDriver] shares the clock face out among exactly the
## participating units — a suppressed panel gives up its pin rather than
## holding a gap open. Defaults to `true` so the driver behaves identically
## with the fan scene open standalone in the editor, where no coordinator
## exists to classify anything.
##
## A plain runtime var, deliberately not an `@export`: it is derived per hover,
## and `.claude/rules/godot-workflow.md` forbids a @tool script writing a
## derived value into an exported property.
var participating := true

## This unit's CURRENT trace-origin angle, in radians clockwise from 12
## o'clock — eased toward the target [FanAnchorDriver] computes for it. Lives
## here rather than in a driver-side Dictionary so it dies with the unit: fan
## instances are created and freed on every hover, and a keyed cache would
## either leak entries or hold freed references.
##
## `NAN` means "never placed" — the driver snaps to the target on first sight
## instead of sweeping in from an arbitrary start. Same reason as above: not an
## `@export`.
var pin_angle := NAN

@onready var _trace: FanTrace = %Trace
@onready var _panel: FanPanel = %Panel

## Bumped by every public entry point ([method play_in] / [method play_out] /
## [method enter_hidden]). An `await` that resumes after a newer sequence has
## already begun checks the generation it started under and bails — without
## this, a fast hover→unhover leaves the IN sequence's pending continuation
## alive, and it unfurls the panel back in *after* OUT started.
var _generation := 0


## Passthrough to this unit's panel (#159 panel wave) — [TooltipFan] collects
## units by group and cannot reach `_panel`, which is private by design. A unit
## whose panel reports no content is never played in; see
## [method FanPanel.has_content].
func has_content() -> bool:
	return _panel == null or _panel.has_content()


## Passthrough to this unit's panel. Kept here (rather than letting the
## coordinator reach into `_panel`) so the unit stays the only thing that knows
## its own composition — same reason [method has_content] exists.
func bind(node: SkillNode, graph: Graph) -> void:
	if _panel != null:
		_panel.bind(node, graph)


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
