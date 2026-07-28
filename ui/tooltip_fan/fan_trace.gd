@tool
class_name FanTrace
extends Node2D

## Tooltip V2 (#159) — one circuit-board trace connector: a [Line2D] that
## draws itself in from an anchor toward a panel, led by a glowing traveling
## tip, then holds a steady settled state. Geometry is delegated to the pure
## [TraceRouter] helper (#217); this scene owns the *drawing* — the reveal
## animation, the tip, and the in → settled → out lifecycle.
##
## Rescoped by #215: the trace is a single PCB / 45°-only family
## ([TraceRouter.Style.PCB]) — a cardinal trunk, an exact 45° diagonal, then a
## cardinal run into the panel. The make-or-break aesthetic knob is
## [member bend_start]: the fraction of the trunk axis covered before the 45°
## break. It spans the whole family on its own — 0 is a pure 45° diagonal from
## the anchor, φ ≈ 0.382 is trunk+45°+leg (the sprout), 1 is a squared 90°
## corner. Seeded at φ and meant to be tuned live, co-varying with the panel
## anchor and sibling traces.
##
## Reveal is by point-count / arc-length truncation of the Line2D (the approach
## [TraceRouter] documents), NOT a dimming brightness ramp: the line keeps a
## CONSTANT color and width across in → settled → out — only how much of it is
## drawn, and the tip position, change. That satisfies the "never dim the
## settled/loop state" rule structurally. Idle life (when [member trace_idle])
## pulses the *tip* alone, never the line.

## φ ≈ 0.382 — the seeded default for [member bend_start]. Asymmetric; usually
## reads better than a flat ⅓. A good starting point for live tuning, not a
## guaranteed optimum.
const PHI_FRACTION := 0.382

## Local-space endpoints of the trace. Authored live in the editor (the panel
## anchor drives `to_point`); the coordinator (#226) sets them at runtime.
@export var from_point := Vector2.ZERO:
	set(value):
		from_point = value
		_rebuild_geometry()
@export var to_point := Vector2(0.0, -120.0):
	set(value):
		to_point = value
		_rebuild_geometry()

@export_group("Route")
## The cardinal direction the trunk leaves the anchor along. Up by default (the
## tooltip fan sprouts upward); exported so a later radial variant can point it
## outward without touching the router. Not normalized here — [TraceRouter] does.
@export var trunk_dir := Vector2(0.0, -1.0):
	set(value):
		trunk_dir = value
		_rebuild_geometry()
## The one route knob: the fraction of the trunk axis covered before the 45°
## break. Spans the whole PCB family — 0 = pure 45° diagonal from the anchor,
## φ ≈ 0.382 = trunk + 45° + cardinal leg, 1 = squared 90° corner. Seeded at φ.
@export_range(0.0, 1.0, 0.001) var bend_start := PHI_FRACTION:
	set(value):
		bend_start = value
		_rebuild_geometry()

@export_group("Look")
@export var line_color := Color(0.4, 0.95, 1.0, 0.9):
	set(value):
		line_color = value
		if _trace:
			_trace.default_color = value
@export var line_width := 2.0:
	set(value):
		line_width = value
		if _trace:
			_trace.width = value
@export var tip_color := Color(0.7, 1.0, 1.0, 1.0):
	set(value):
		tip_color = value
		if _tip:
			_tip.self_modulate = value
@export var tip_scale := 1.0:
	set(value):
		tip_scale = value
		if _tip and not _is_animating:
			_tip.scale = Vector2.ONE * value

@export_group("Motion")
@export var draw_in_duration := 0.28
@export var erase_duration := 0.18
## When on, the settled trace keeps a soft looping pulse on the *tip* (never on
## the line — that would break the constant-brightness rule). Kept as a toggle
## until a favourite idle style lands (#215).
@export var trace_idle := false:
	set(value):
		trace_idle = value
		if is_node_ready() and not Engine.is_editor_hint():
			_refresh_idle()

## 0 = nothing drawn (hidden), 1 = fully drawn. Drives arc-length truncation of
## the Line2D and the tip position. Assigning it re-applies the reveal; the
## lifecycle tweens animate it.
@export_range(0.,1.,0.01) var progress := 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_apply_progress()

@onready var _trace: Line2D = %Trace
@onready var _tip: Sprite2D = %Tip

## Full computed polyline (progress == 1). Cached so reveal truncation doesn't
## re-run TraceRouter every frame of the tween.
var _full_points := PackedVector2Array()
var _lifecycle_tween: Tween = null
var _idle_tween: Tween = null
var _is_animating := false


func _ready() -> void:
	_trace.default_color = line_color
	_trace.width = line_width
	_tip.self_modulate = tip_color
	_rebuild_geometry()
	if Engine.is_editor_hint():
		# Author-time: show the whole trace so panel/anchor placement is
		# witnessable while dragging. Pure visual setup, safe under @tool.
		progress = 1.0
		return
	# Runtime: start hidden; the coordinator/FanUnit calls play_in().
	progress = 0.0
	_tip.visible = false


## Recomputes the full polyline from the current endpoints + route exports and
## re-applies the current progress. Safe to call before _ready (no-ops until the
## Line2D exists).
func _rebuild_geometry() -> void:
	if _trace == null:
		return
	_full_points = TraceRouter.compute_trace_points(
		from_point, to_point, TraceRouter.Style.PCB, _router_params())
	_apply_progress()


## Translates this scene's exports into the params [TraceRouter]'s PCB route
## expects: the trunk fraction and the trunk direction.
func _router_params() -> Dictionary:
	return {
		"trunk": bend_start,
		"trunk_dir": trunk_dir,
	}


## Truncates the cached polyline to the current `progress` (by arc length) and
## parks the tip at the drawn head. Constant line color/width throughout — only
## the drawn extent and tip move.
func _apply_progress() -> void:
	if _trace == null:
		return
	var slice := _polyline_at(_full_points, progress)
	_trace.points = slice.points
	if _tip:
		_tip.position = slice.head
		# The tip is the traveling head: lit only while the trace is being
		# drawn (0 < progress < 1). At progress == 1 it auto-extinguishes — the
		# settled state is the constant-lit line alone. Applies in editor too,
		# so the sandbox host (#233) animates in the viewport. The idle option
		# (below) re-lights it explicitly.
		_tip.visible = progress > 0.0 and progress < 1.0


## Returns {points, head}: the sub-polyline of `points` from its start up to the
## point at fractional arc length `t`, and that head point. Deterministic —
## the unit under test. `t == 0` yields a degenerate start; `t == 1` the whole
## line.
static func _polyline_at(points: PackedVector2Array, t: float) -> Dictionary:
	if points.size() < 2:
		var only := points[0] if points.size() == 1 else Vector2.ZERO
		return {"points": points, "head": only}
	t = clampf(t, 0.0, 1.0)
	var seg_len := PackedFloat32Array()
	var total := 0.0
	for i in range(points.size() - 1):
		var l := points[i].distance_to(points[i + 1])
		seg_len.append(l)
		total += l
	if total <= 0.0:
		return {"points": PackedVector2Array([points[0], points[0]]), "head": points[0]}
	var target := t * total
	var out := PackedVector2Array([points[0]])
	var acc := 0.0
	for i in range(points.size() - 1):
		var l := seg_len[i]
		if acc + l >= target:
			var f := (target - acc) / l if l > 0.0 else 0.0
			var head := points[i].lerp(points[i + 1], f)
			out.append(head)
			return {"points": out, "head": head}
		out.append(points[i + 1])
		acc += l
	var last := points[points.size() - 1]
	return {"points": points, "head": last}


## Animates the trace drawing itself in (progress 0 → 1) with the tip travelling
## along it, then settles (tip parks, optional idle pulse). Returns the Tween so
## a caller (FanUnit) can `await tween.finished` to sequence the panel unfurl.
func play_in() -> Tween:
	_kill_idle()
	_stop_lifecycle()
	_is_animating = true
	_tip.visible = true
	_tip.scale = Vector2.ONE * tip_scale
	progress = 0.0
	_lifecycle_tween = create_tween()
	_lifecycle_tween.tween_property(self, "progress", 1.0, draw_in_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_lifecycle_tween.tween_callback(_on_draw_in_finished)
	return _lifecycle_tween


## Animates the trace erasing (progress 1 → 0). Returns the Tween for sequencing.
func play_out() -> Tween:
	_kill_idle()
	_stop_lifecycle()
	_is_animating = true
	_tip.visible = true
	_lifecycle_tween = create_tween()
	_lifecycle_tween.tween_property(self, "progress", 0.0, erase_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_lifecycle_tween.tween_callback(func() -> void:
		_is_animating = false
		_tip.visible = false)
	return _lifecycle_tween


func _on_draw_in_finished() -> void:
	_is_animating = false
	# Settled: progress == 1 draws the whole line and extinguishes the tip
	# (see _apply_progress). The LINE brightness is unchanged from the in-state
	# (same default_color/width) — constant by construction. If idle is on, the
	# tip is re-lit and breathes; otherwise the settled state is the bare line.
	progress = 1.0
	_refresh_idle()


## (Re)starts or stops the settled-state idle pulse on the tip per
## [member trace_idle]. The line is never touched — only the re-lit tip breathes.
func _refresh_idle() -> void:
	_kill_idle()
	if not trace_idle or _is_animating or _tip == null:
		return
	_tip.position = _full_points[_full_points.size() - 1] if not _full_points.is_empty() else to_point
	_tip.visible = true
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_tip, "scale", Vector2.ONE * tip_scale * 1.35, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_tip, "scale", Vector2.ONE * tip_scale, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_lifecycle() -> void:
	if _lifecycle_tween != null and _lifecycle_tween.is_valid():
		_lifecycle_tween.kill()
	_lifecycle_tween = null


func _kill_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null
