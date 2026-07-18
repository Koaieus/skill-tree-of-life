@tool
extends Node2D

## #233 (scaled to #222): an in-editor preview harness for [FanTrace].
##
## The shipped FanTrace scene draws a static settled line when opened alone —
## you can't witness the draw-in → extinguish choreography, and its endpoints
## are inspector values with no viewport handle. This dev-only host fixes both:
##
##   - Each trace is paired with a [Marker2D] whose position drives that trace's
##     `to_point`. Drag the marker in the 2D viewport and the trace re-routes
##     live (the trace's own position is the "from" anchor — drag that too).
##   - The tool buttons run a playhead in `_process` (which @tool nodes receive
##     in the editor), so ▶ actually animates the reveal in the viewport:
##     line grows a=0 → full with the bright tip leading, then the tip
##     extinguishes at arrival. ∞ loops draw-in ⇄ erase for continuous tuning.
##
## Nothing here ships — it's the authoring surface for choosing a trace look
## (bend_start, bend, colors) against real motion.

@export_tool_button("▶  Play draw-in") var _play_action: Callable = _play_draw_in
@export_tool_button("⟲  Play erase") var _erase_action: Callable = _play_erase
@export_tool_button("∞  Toggle loop") var _loop_action: Callable = _toggle_loop
@export_tool_button("■  Reset to settled") var _reset_action: Callable = _reset_settled

@export_range(0.1, 3.0, 0.05) var draw_in_duration := 0.7
@export_range(0.1, 3.0, 0.05) var erase_duration := 0.45
## Pause at full before erase when looping.
@export_range(0.0, 2.0, 0.05) var hold_duration := 0.6

## Index-matched pairs, wired in the scene. `trace_paths[i]`'s `to_point` is
## driven by `target_paths[i]`'s position each frame.
@export var trace_paths: Array[NodePath] = []
@export var target_paths: Array[NodePath] = []

enum _Phase { IDLE, DRAW_IN, HOLD, ERASE }

var _traces: Array[FanTrace] = []
var _targets: Array[Marker2D] = []
var _phase := _Phase.IDLE
var _clock := 0.0
var _looping := false


func _ready() -> void:
	_resolve_pairs()
	set_process(true)


func _resolve_pairs() -> void:
	_traces.clear()
	_targets.clear()
	for p in trace_paths:
		_traces.append(get_node_or_null(p) as FanTrace)
	for p in target_paths:
		_targets.append(get_node_or_null(p) as Marker2D)


func _process(_delta: float) -> void:
	_sync_endpoints()
	if _phase == _Phase.IDLE:
		return
	_clock += _delta
	match _phase:
		_Phase.DRAW_IN:
			var p := clampf(_clock / draw_in_duration, 0.0, 1.0)
			_set_progress(p)
			if p >= 1.0:
				_enter(_Phase.HOLD)
		_Phase.HOLD:
			if _clock >= hold_duration:
				_enter(_Phase.ERASE if _looping else _Phase.IDLE)
		_Phase.ERASE:
			var e := clampf(_clock / erase_duration, 0.0, 1.0)
			_set_progress(1.0 - e)
			if e >= 1.0:
				_enter(_Phase.DRAW_IN if _looping else _Phase.IDLE)


## Drives each trace's `to_point` from its paired marker so dragging the marker
## in the editor re-routes the trace live. Marker positions are host-local;
## endpoints are trace-local, hence the offset by the trace's own position.
func _sync_endpoints() -> void:
	for i in mini(_traces.size(), _targets.size()):
		var tr := _traces[i]
		var mk := _targets[i]
		if tr != null and mk != null:
			tr.to_point = mk.position - tr.position


func _set_progress(p: float) -> void:
	for tr in _traces:
		if tr != null:
			tr.progress = p


func _enter(phase: int) -> void:
	_phase = phase
	_clock = 0.0


func _play_draw_in() -> void:
	_looping = false
	_resolve_pairs()
	_set_progress(0.0)
	_enter(_Phase.DRAW_IN)


func _play_erase() -> void:
	_looping = false
	_resolve_pairs()
	_set_progress(1.0)
	_enter(_Phase.ERASE)


func _toggle_loop() -> void:
	_looping = not _looping
	_resolve_pairs()
	if _looping:
		_set_progress(0.0)
		_enter(_Phase.DRAW_IN)
	else:
		_enter(_Phase.IDLE)


func _reset_settled() -> void:
	_looping = false
	_resolve_pairs()
	_enter(_Phase.IDLE)
	_set_progress(1.0)
