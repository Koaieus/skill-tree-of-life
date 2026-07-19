@tool
extends Node2D

## #233 / #159 — in-editor preview harness for the circuit-fan node tooltip.
##
## Grew (this pass) from a 3-line trace tuner into a full **fan-out** preview: a
## mock skill node at the origin, five [FanTrace] traces sprouting upward as a
## tight ~4px-apart trunk bundle, then branching to placeholder destinations —
## four corner panels ([HoloPanel], NNW / NNE / NWW / NEE) plus a central-top row
## of stat-modifier tiles ([ModSlabRow]). Placeholders now, filled with real node
## info one panel at a time later (epic #159, phase 2).
##
## Everything is driven off a single clock (`_clock`, in seconds) — no per-unit
## Tween chains. Each unit `i` starts `i * stagger_time` into the timeline; its
## trace draws in over `draw_time`, then its panel reveals (scale + fade) over
## `panel_time`. Reversing the clock retracts the whole fan for free. This matches
## the spell-VFX clock contract: fixed clock, everyone reads progress(0..1), no
## hop gates the next.
##
## Three drive modes, selectable from the host tab's buttons:
##   - MANUAL — ▶ / ⟲ fire a one-shot draw-in / erase.
##   - LOOP   — ∞ auto-cycles draw-in ⇄ hold ⇄ erase for continuous tuning.
##   - HOVER  — ☌ opens the fan while the mouse is within `hover_radius` of the
##     mock node and retracts it on leave. @tool `_process` reads the viewport
##     mouse directly (distance test) — no physics picking, which is unreliable
##     in an embedded editor SubViewport.
##
## Nothing here ships; it's the authoring surface. The draggable [Marker2D]
## anchors are the tuning handles — drag one and its trace re-routes and its
## destination follows live.

## Inspector buttons for driving the preview when opened directly. The host tab
## (fan_trace_panel) drives the same public methods from on-screen buttons.
@export_tool_button("▶  Play draw-in") var _play_action: Callable = play_draw_in
@export_tool_button("⟲  Play erase") var _erase_action: Callable = play_erase
@export_tool_button("∞  Toggle loop") var _loop_action: Callable = toggle_loop
@export_tool_button("■  Reset to settled") var _reset_action: Callable = reset_settled

@export_group("Timing")
## Seconds for one trace to draw itself in (0 → full).
@export_range(0.05, 2.0, 0.01) var draw_time := 0.30
## Seconds for a destination panel to reveal (scale + fade) once its trace lands.
@export_range(0.05, 2.0, 0.01) var panel_time := 0.22
## Head-start between successive units — unit `i` begins `i * stagger_time` in.
@export_range(0.0, 0.5, 0.01) var stagger_time := 0.06
## Full-open dwell before the loop retracts.
@export_range(0.0, 3.0, 0.05) var hold_duration := 0.7
## Seconds for the whole fan to retract (whatever its open depth).
@export_range(0.05, 2.0, 0.01) var erase_duration := 0.35

@export_group("Panel reveal")
## Scale a destination starts at before revealing (unfolds up to 1.0 from the
## trace tip, which is the destination's own origin).
@export_range(0.5, 1.0, 0.01) var panel_start_scale := 0.82

@export_group("Hover")
## Radius (px, sandbox-local) around the mock node that counts as "hovering".
@export_range(10.0, 200.0, 1.0) var hover_radius := 46.0

@export_group("Wiring")
## Index-matched triples wired in the scene: `trace_paths[i]` routes to
## `marker_paths[i]`, and `dest_paths[i]` (the placeholder content) rides the
## same marker and reveals after the trace lands.
@export var trace_paths: Array[NodePath] = []
@export var marker_paths: Array[NodePath] = []
@export var dest_paths: Array[NodePath] = []

enum _Mode { MANUAL, LOOP, HOVER }

var _traces: Array[FanTrace] = []
var _markers: Array[Marker2D] = []
var _dests: Array[Node2D] = []

var _mode := _Mode.MANUAL
var _clock := 0.0
var _target_open := true
var _hold_clock := 0.0
var _hovering := false


func _ready() -> void:
	_resolve()
	# Open by default so opening the scene/tab shows the settled fan.
	_clock = _open_total()
	_target_open = true
	set_process(true)


func _resolve() -> void:
	_traces.assign(trace_paths.map(func(p): return get_node_or_null(p) as FanTrace))
	_markers.assign(marker_paths.map(func(p): return get_node_or_null(p) as Marker2D))
	_dests.assign(dest_paths.map(func(p): return get_node_or_null(p) as Node2D))


## Total timeline length: the last unit's start plus one full draw + reveal.
func _open_total() -> float:
	var last := maxi(_unit_count() - 1, 0)
	return last * stagger_time + draw_time + panel_time


func _unit_count() -> int:
	return mini(_traces.size(), mini(_markers.size(), _dests.size()))


func _process(delta: float) -> void:
	_sync_anchors()
	_advance(delta)
	_apply(_clock)
	if Engine.is_editor_hint():
		queue_redraw()  # keep the hover ring live in the editor viewport


## Drives each trace's `to_point` and its destination's position from the shared
## marker, so dragging a marker in the editor re-routes both live. Marker/dest
## positions are host-local; a trace's endpoint is trace-local, hence the offset.
func _sync_anchors() -> void:
	for i in _unit_count():
		var mk := _markers[i]
		if mk == null:
			continue
		if _traces[i] != null:
			_traces[i].to_point = mk.position - _traces[i].position
		if _dests[i] != null:
			_dests[i].position = mk.position


## Steps the clock toward its target (open/closed), handling the loop dwell and
## reading the hover distance test. All modes share this one integrator.
func _advance(delta: float) -> void:
	var total := _open_total()
	match _mode:
		_Mode.HOVER:
			_hovering = get_local_mouse_position().length() <= hover_radius
			_target_open = _hovering
		_Mode.LOOP:
			# Toggle the target at each end after the dwell; the integrator below
			# does the actual easing between.
			if _target_open and _clock >= total:
				_hold_clock += delta
				if _hold_clock >= hold_duration:
					_target_open = false
					_hold_clock = 0.0
			elif not _target_open and _clock <= 0.0:
				_hold_clock += delta
				if _hold_clock >= hold_duration:
					_target_open = true
					_hold_clock = 0.0
		_Mode.MANUAL:
			pass

	if _target_open:
		_clock = minf(_clock + delta, total)
	else:
		var rate := total / maxf(erase_duration, 0.001)
		_clock = maxf(_clock - delta * rate, 0.0)


## Applies the timeline at `clock` to every unit: trace reveal, then panel
## scale + fade. Pure function of the clock — forward and reverse for free.
func _apply(clock: float) -> void:
	for i in _unit_count():
		var local := clock - i * stagger_time
		if _traces[i] != null:
			_traces[i].progress = clampf(local / maxf(draw_time, 0.001), 0.0, 1.0)
		var dest := _dests[i]
		if dest == null:
			continue
		var raw := clampf((local - draw_time) / maxf(panel_time, 0.001), 0.0, 1.0)
		if dest is FanPanel:
			(dest as FanPanel).set_progress(raw)
			continue
		var e := _ease_out(raw)
		dest.scale = Vector2.ONE * lerpf(panel_start_scale, 1.0, e)
		var m := dest.modulate
		m.a = e
		dest.modulate = m


## Cubic ease-out — snappy landing for the panel unfold.
static func _ease_out(t: float) -> float:
	var inv := 1.0 - t
	return 1.0 - inv * inv * inv


func _draw() -> void:
	# Mock skill node at the origin: a neon ring that brightens as the fan opens.
	var openness := clampf(_clock / maxf(_open_total(), 0.001), 0.0, 1.0)
	var base := Color(0.4, 0.95, 1.0)
	draw_circle(Vector2.ZERO, 13.0, Color(base.r, base.g, base.b, 0.15 + 0.25 * openness))
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 48, Color(base, 0.5 + 0.5 * openness), 2.0, true)
	if _mode == _Mode.HOVER:
		var ring := Color(0.7, 1.0, 1.0, 0.18 if _hovering else 0.08)
		draw_arc(Vector2.ZERO, hover_radius, 0.0, TAU, 64, ring, 1.0, true)


# --- Public control surface (host-tab buttons + inspector) --------------------

func play_draw_in() -> void:
	_mode = _Mode.MANUAL
	_resolve()
	_target_open = true


func play_erase() -> void:
	_mode = _Mode.MANUAL
	_resolve()
	_target_open = false


func toggle_loop() -> void:
	set_looping(_mode != _Mode.LOOP)


## Turn the draw-in ⇄ erase loop on/off (drives the host tab's ∞ toggle).
func set_looping(on: bool) -> void:
	_resolve()
	if on:
		_mode = _Mode.LOOP
		_target_open = true
		_hold_clock = 0.0
	else:
		_mode = _Mode.MANUAL


## Turn hover-driven opening on/off (drives the host tab's ☌ toggle). While on,
## the fan tracks the mouse: open within `hover_radius` of the node, closed out.
func set_hover_driven(on: bool) -> void:
	_resolve()
	if on:
		_mode = _Mode.HOVER
		_target_open = false
		_clock = 0.0
	else:
		_mode = _Mode.MANUAL


func reset_settled() -> void:
	_resolve()
	_mode = _Mode.MANUAL
	_target_open = true
	_clock = _open_total()
