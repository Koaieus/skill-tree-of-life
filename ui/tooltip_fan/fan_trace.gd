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
## settled/loop state" rule structurally. Idle life (when an idle animation is
## assigned to [member idle_anim]) pulses the *tip* alone, never the line.
##
## The trace does not simply "start": it IGNITES. The first
## [member ignite_fraction] of `progress` is a lead-in during which the line is
## still zero-length and only the origin pad blooms — a solder-pad dot at the
## clock pin that pops bright, then relaxes to a small steady marker while the
## line shoots out of it. With N traces staggered around the node's rim, that
## reads as the chip's pins energizing before the callouts fly out.
##
## The pad is folded into `progress` rather than prepended as its own tween leg,
## and that is the load-bearing choice: everything stays a pure function of
## `progress`, so scrubbing (the sandbox), reversing from a half-open state, and
## [method FanUnit.enter_hidden]'s hard `progress = 0` all keep working with no
## extra bookkeeping and no duration arithmetic in [FanUnit].

## φ ≈ 0.382 — the seeded default for [member bend_start]. Asymmetric; usually
## reads better than a flat ⅓. A good starting point for live tuning, not a
## guaranteed optimum.
const PHI_FRACTION := 0.382

## Local-space endpoints of the trace. Authored live in the editor (the panel
## anchor drives `to_point`); the coordinator (#226) sets them at runtime.
##
## Both guard on equality — not against recursion (assigning a property inside
## its own setter doesn't recurse), but because [FanAnchorDriver] rewrites them
## every frame for every trace. Without the skip, a settled fan would re-run
## TraceRouter and re-slice the Line2D continuously for values that never moved.
@export var from_point := Vector2.ZERO:
	set(value):
		if from_point.is_equal_approx(value):
			return
		from_point = value
		_rebuild_geometry()
@export var to_point := Vector2(0.0, -120.0):
	set(value):
		if to_point.is_equal_approx(value):
			return
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
## Fixed trunk length in pixels. When > 0 it REPLACES [member bend_start] —
## the trunk is this long regardless of how far the panel is (clamped so it
## can't overshoot the trunk axis).
##
## The difference matters for a fan: `bend_start` is a *fraction* of the trunk
## axis span, so a near panel gets a short trunk and a far one a long trunk. A
## fixed length makes every trace leave the node in a uniform bundle before
## diverging — which is what makes the chip read as a chip. 0 keeps the
## fractional behaviour.
##
## Usually DERIVED rather than authored here: [FanAnchorDriver] solves it every
## frame from the unit's [member FanUnit.arrival_axis] /
## [member FanUnit.trunk_length]. Hence the equality skip — same reason
## `from_point`/`to_point` carry one (a rewrite of an unchanged value would
## re-run TraceRouter and re-slice the Line2D every frame), and same
## non-reason: assigning a property inside its own setter doesn't recurse.
@export_range(0.0, 200.0, 1.0, "or_greater") var trunk_length := 0.0:
	set(value):
		if is_equal_approx(trunk_length, value):
			return
		trunk_length = value
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

@export_group("Origin pad")
## Fraction of `progress` spent igniting the origin pad before the line starts
## drawing. 0 disables the lead-in entirely (the pad snaps to its settled look
## and the reveal is exactly the pre-#-pad behaviour); ~0.2 of a 0.28s draw is
## the ~55ms pop this is tuned for. Above ~0.4 the pause before the line moves
## starts reading as a hitch rather than an ignition.
@export_range(0.0, 0.6, 0.01) var ignite_fraction := 0.22:
	set(value):
		ignite_fraction = value
		_apply_progress()
@export var pad_color := Color(0.7, 1.0, 1.0, 1.0):
	set(value):
		pad_color = value
		if _pad:
			_pad.self_modulate = value
## Size of the pad once the line is on its way — the steady "this trace starts
## here" marker that stays for the whole settled state.
@export_range(0.0, 3.0, 0.01) var pad_scale := 0.75:
	set(value):
		pad_scale = value
		_apply_progress()
## Size the pad overshoots to at the peak of ignition, before relaxing to
## [member pad_scale]. The bloom: > pad_scale is the whole point.
@export_range(0.0, 4.0, 0.01) var pad_flash_scale := 1.6:
	set(value):
		pad_flash_scale = value
		_apply_progress()

@export_group("Motion")
@export var draw_in_duration := 0.28
@export var erase_duration := 0.18

@export_group("Idle")
## The settled-state idle-loop settings for this trace (#234) — or `null` to
## keep the settled trace a bare, constant-lit line (the default; nothing in
## the shipped fan assigns one). A self-contained settings object: swap a
## different [FanAnimation] `.tres` to change the pulse, set this to `null` to
## turn idle off. When on, the settled trace keeps a soft looping pulse on the
## *tip* (never on the line — that would break the constant-brightness rule).
## Only [member FanAnimation.period] and [member FanAnimation.pulse_scale] are
## read; the panel-only knobs are ignored.
@export var idle_anim: FanAnimation = null:
	set(value):
		idle_anim = value
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
@onready var _pad: Sprite2D = %Pad

## Full computed polyline (progress == 1). Cached so reveal truncation doesn't
## re-run TraceRouter every frame of the tween.
var _full_points := PackedVector2Array()
var _lifecycle_tween: Tween = null
var _idle_tween: Tween = null
var _is_animating := false

## True while an OUT sequence owns the lifecycle tween. The tip is the *arrival*
## head — it exists to say "the signal is going somewhere". On the way out
## there's nothing to arrive at, so it's suppressed and the line simply retracts
## into its pad; the pad extinguishing is the closing beat. Nothing replaces it.
##
## Direction can't be inferred from `progress` alone (the setter sees one value,
## not a delta), and inferring it from a delta would misread the editor's
## scrubber. So it's set explicitly by the two entry points — which also means
## a scrubbed preview still shows the tip in both directions, on purpose: the
## sandbox is an authoring surface, not the shipped read.
var _erasing := false


func _ready() -> void:
	_trace.default_color = line_color
	_trace.width = line_width
	_tip.self_modulate = tip_color
	_pad.self_modulate = pad_color
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
		from_point, to_point, TraceRouter.Style.PCB, route_params())
	_apply_progress()


## Translates this scene's exports into the params [TraceRouter]'s PCB route
## expects: the trunk fraction, the trunk direction, and the fixed trunk length.
##
## Public because it is the ONE place a route is specified — [FanAnchor] and the
## tests both reconstruct this trace's route through it rather than hand-building
## the dict. Hand-built copies drift (one omits `trunk_px` and silently describes
## a different line than the one on screen), which is exactly the bug that made
## it public.
func route_params() -> Dictionary:
	return {
		"trunk": bend_start,
		"trunk_dir": trunk_dir,
		"trunk_px": trunk_length,
	}


## Splits `progress` into the two bands the reveal is made of — ignition, then
## draw — and applies both. Truncates the cached polyline to the draw band's
## share (by arc length) and parks the tip at the drawn head. Constant line
## color/width throughout: only the drawn extent, the tip, and the pad move.
func _apply_progress() -> void:
	if _trace == null:
		return
	# `line_t` is progress renormalized over the post-ignition band, so the line
	# still covers its full length in whatever time is left. Everything below is
	# a pure function of these two — which is what makes reverse-from-anywhere
	# and editor scrubbing fall out for free.
	var ignite_t := 1.0 if ignite_fraction <= 0.0 else clampf(progress / ignite_fraction, 0.0, 1.0)
	var line_t := progress if ignite_fraction >= 1.0 \
		else clampf((progress - ignite_fraction) / (1.0 - ignite_fraction), 0.0, 1.0)
	var slice := _polyline_at(_full_points, line_t)
	_trace.points = slice.points
	if _tip:
		_tip.position = slice.head
		# The tip is the traveling head: lit only while the trace is being
		# drawn IN (0 < line_t < 1). At line_t == 1 it auto-extinguishes — the
		# settled state is the constant-lit line alone — and it never lights at
		# all on the way out (see `_erasing`). Applies in editor too, so the
		# sandbox host (#233) animates in the viewport. The idle option (below)
		# re-lights it explicitly.
		_tip.visible = line_t > 0.0 and line_t < 1.0 and not _erasing
	_apply_pad(ignite_t, line_t)


## The origin pad: blooms to [member pad_flash_scale] across the ignition band,
## then relaxes to [member pad_scale] as the line draws. Alpha rides ignition
## alone, so the pad is fully lit by the time the line leaves it and stays lit
## for the whole settled state — the trace visibly comes FROM somewhere.
func _apply_pad(ignite_t: float, line_t: float) -> void:
	if _pad == null:
		return
	# Sits at the polyline's own head-of-tail, not `from_point`, so a router that
	# ever insets its first point keeps the pad on the line rather than beside it.
	_pad.position = _full_points[0] if not _full_points.is_empty() else from_point
	var bloom := _ease_out(ignite_t)
	var peak := lerpf(0.0, pad_flash_scale, bloom)
	# The relax leg is deliberately front-loaded against the line's own ease-out:
	# the flash is spent in the first third of the draw, so what remains for the
	# settled state is the small steady marker, not a lingering blob.
	var settle := _ease_out(minf(line_t * 3.0, 1.0))
	_pad.scale = Vector2.ONE * lerpf(peak, pad_scale, settle)
	_pad.modulate.a = bloom
	_pad.visible = bloom > 0.0


## Cubic ease-out. Shared by the pad's bloom and relax legs.
static func _ease_out(t: float) -> float:
	var inv := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - inv * inv * inv


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
## Animates the trace igniting and drawing itself in (progress 0 → 1) with the
## tip travelling along it, then settles (tip parks, optional idle pulse).
## Returns the Tween so a caller (FanUnit) can `await tween.finished` to sequence
## the panel unfurl.
##
## Two legs, split at [member ignite_fraction], so each band gets its own
## easing: the pad ignites at a constant rate (its own cubic bloom does the
## shaping) and the line still lands decelerating. Total duration is exactly
## `draw_in_duration` either way — the split is invisible to FanUnit.
func play_in() -> Tween:
	_kill_idle()
	_stop_lifecycle()
	_is_animating = true
	_erasing = false
	_tip.scale = Vector2.ONE * tip_scale
	progress = 0.0
	_lifecycle_tween = create_tween()
	if ignite_fraction > 0.0:
		_lifecycle_tween.tween_property(self, "progress", ignite_fraction,
			draw_in_duration * ignite_fraction).set_trans(Tween.TRANS_LINEAR)
	_lifecycle_tween.tween_property(self, "progress", 1.0,
		draw_in_duration * (1.0 - ignite_fraction)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_lifecycle_tween.tween_callback(_on_draw_in_finished)
	return _lifecycle_tween


## Animates the trace erasing (progress 1 → 0) — the mirror read: the line
## retracts into the pad, then the pad itself extinguishes. Returns the Tween for
## sequencing.
func play_out() -> Tween:
	_kill_idle()
	_stop_lifecycle()
	_is_animating = true
	# Suppress the arrival tip for the whole retraction — including the frame
	# this is called on, if an interrupt caught it mid-flight.
	_erasing = true
	_tip.visible = false
	_lifecycle_tween = create_tween()
	if ignite_fraction > 0.0 and progress > ignite_fraction:
		_lifecycle_tween.tween_property(self, "progress", ignite_fraction,
			erase_duration * (1.0 - ignite_fraction)) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_lifecycle_tween.tween_property(self, "progress", 0.0,
			erase_duration * ignite_fraction).set_trans(Tween.TRANS_LINEAR)
	else:
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
## [member idle_anim]. The line is never touched — only the re-lit tip breathes.
## The period is floored (~0.05s) so a stray 0 in the resource can never spin a
## looped tween per-frame.
func _refresh_idle() -> void:
	_kill_idle()
	if idle_anim == null or _is_animating or _tip == null:
		return
	var period := maxf(idle_anim.period, 0.05)
	_tip.position = _full_points[_full_points.size() - 1] if not _full_points.is_empty() else to_point
	_tip.visible = true
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_tip, "scale", Vector2.ONE * tip_scale * idle_anim.pulse_scale, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_tip, "scale", Vector2.ONE * tip_scale, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_lifecycle() -> void:
	if _lifecycle_tween != null and _lifecycle_tween.is_valid():
		_lifecycle_tween.kill()
	_lifecycle_tween = null


func _kill_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null
