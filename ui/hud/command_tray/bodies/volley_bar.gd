@tool
class_name VolleyBar
extends Control
## The notched volley bar (#954): one bar for the whole volley, `N / max`,
## typed segments painted in roster order up to N, and a notch at every wave
## boundary. Owner (2026-09-19): the notches are wave boundaries and nothing
## else — they read as "how many waves this volley burns"; there is no kill
## notch. Pure view: it draws what [method set_volley] hands it and asks for
## changes through its signals. Scroll = ±1, Shift-scroll = ±wave, click /
## drag = set N at the pointer.
##
## During a launch the bar reacts to the volley's beats (#1046): each placed
## arrow charges its slice to `Emissive.at(tint, 3)`, each released arrow has
## the dim tint eat that slice from below like a magazine round. The beats
## are forwarded by [RangedBody] from `Events`; the bar never reads the
## coordinator. While the plan is launching [method set_volley] is a HOLD —
## the drained strips (and the geometry they sit on) stay put until the
## first refresh after control resumes, which clears them.

## Ask the owner to move N by [param delta] arrows, or by [param delta] waves.
signal step_requested(delta: int, by_wave: bool)
## Ask the owner to set N to [param n] (click / drag on the track).
signal set_requested(n: int)

const TRACK_H: float = 18.0
const LABEL_W: float = 64.0
const NOTCH_COLOR := Color(0.06, 0.08, 0.12, 0.9)
const TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.06)
const TRACK_EDGE := Color(0.47, 0.55, 0.75, 0.25)
const EMPTY_TINT := Color(0.784, 0.824, 0.902, 0.35)
## Segment tint per ammo type id; anything unlisted paints amber.
const TYPE_TINTS: Dictionary = {
	&"arrow": Color(0.3187, 0.7773, 0.4484, 0.95),
	&"poison": Color(0.55, 0.38, 0.85, 0.95),
}
const FALLBACK_TINT := Color(0.9, 0.65, 0.25, 0.95)
## How far a fired slice is darkened — a spent chamber, not a glow tier.
const FIRED_DIM: float = 0.6
## Glow tier a placed arrow charges its slice to (`Emissive.at` stops).
const CHARGE_STOPS: float = 3.0
const CHARGE_TIME: float = 0.08
const DRAIN_TIME: float = 0.15

## Widest a single arrow shaft paints, px (tentative). Thin shafts read as
## arrows; a sparse volley left-packs instead of stretching.
@export var max_shaft_width: float = 6.0:
	set(v):
		max_shaft_width = maxf(1.0, v)
		queue_redraw()
## Gap between neighbouring shafts, px (tentative).
@export var shaft_gap: float = 2.0:
	set(v):
		shaft_gap = maxf(0.0, v)
		queue_redraw()

var n: int = 0
var max_n: int = 0
## Cumulative wave sizes strictly below max, e.g. 3, 6, 9 for max 11.
var notches: PackedInt32Array = PackedInt32Array()
## `[{type_id, count}]` in roster order, Σ count == n.
var segments: Array[Dictionary] = []

var _font: Font
var _white_tex: Texture2D
@onready var _shaft_layer: Control = %ShaftLayer
var _dragging := false

## Per-arrow charge strip of the launched volley, 0 = normal, 1 = lit; the
## painted value, written by the placement tweens.
var _arrow_state: PackedFloat32Array = PackedFloat32Array()
## Per-arrow drain strip, 0..1 = how far the dim has eaten the slice upward.
var _arrow_fired: PackedFloat32Array = PackedFloat32Array()
## What the tweens aim at — the schedule, readable without a frame.
var arrow_state_target: PackedFloat32Array = PackedFloat32Array()
var arrow_fired_target: PackedFloat32Array = PackedFloat32Array()
var _strip_tweens: Array[Tween] = []


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, TRACK_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	_shaft_layer.draw.connect(_draw_shafts)


## Repaint the bar from the plan. [param hold] true (the plan is launching)
## keeps everything — strips and geometry — so the drain plays out on the
## volley that fired; the first call with it false clears the strips.
func set_volley(p_n: int, p_max: int, p_notches: PackedInt32Array, p_segments: Array[Dictionary], hold: bool = false) -> void:
	if hold:
		return
	_clear_strips()
	n = p_n
	max_n = p_max
	notches = p_notches
	segments = p_segments
	tooltip_text = "%d / %d arrows · scroll ±1 · Shift+scroll ±wave · M = max" % [n, max_n]
	queue_redraw()


## Beat: arrow [param index] of [param total] parked at its leaf — charge
## its slice. The beat's total sizes the strips; it is the volley that fired.
func on_arrow_placed(index: int, total: int) -> void:
	_size_strips(total)
	if index < 0 or index >= total:
		return
	arrow_state_target[index] = 1.0
	_tween_strip(_set_state, index, _arrow_state[index], 1.0, CHARGE_TIME)


## Beat: arrow [param index] of [param total] left its leaf — the dim eats
## its slice upward.
func on_arrow_released(index: int, total: int) -> void:
	_size_strips(total)
	if index < 0 or index >= total:
		return
	arrow_fired_target[index] = 1.0
	_tween_strip(_set_fired, index, _arrow_fired[index], 1.0, DRAIN_TIME)


## Pure: how one arrow slice paints for a charge `state` (0 = plain tint,
## 1 = `Emissive.at(tint, CHARGE_STOPS)`) and a drain `fired` fraction —
## `lit` covers the slice, `dim` covers its bottom `fired` of the height.
static func paint_slice(state: float, fired: float, tint: Color) -> Dictionary:
	return {
		"lit": Emissive.at(tint, CHARGE_STOPS * clampf(state, 0.0, 1.0)),
		"dim": tint.darkened(FIRED_DIM),
		"fired": clampf(fired, 0.0, 1.0),
	}


func _size_strips(total: int) -> void:
	if _arrow_state.size() == total:
		return
	_arrow_state.resize(total)
	_arrow_fired.resize(total)
	arrow_state_target.resize(total)
	arrow_fired_target.resize(total)


func _clear_strips() -> void:
	for t in _strip_tweens:
		if t != null and t.is_valid():
			t.kill()
	_strip_tweens.clear()
	_arrow_state = PackedFloat32Array()
	_arrow_fired = PackedFloat32Array()
	arrow_state_target = PackedFloat32Array()
	arrow_fired_target = PackedFloat32Array()


func _tween_strip(setter: Callable, index: int, from: float, to: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_method(setter.bind(index), from, to, secs)
	_strip_tweens.append(tw)


func _set_state(v: float, index: int) -> void:
	if index < _arrow_state.size():
		_arrow_state[index] = v
		queue_redraw()


func _set_fired(v: float, index: int) -> void:
	if index < _arrow_fired.size():
		_arrow_fired[index] = v
		queue_redraw()


## The tint of arrow [param index]: the segment whose cumulative count
## covers it, or the fallback when the strips outrun the fill.
static func _slice_tint(index: int, p_segments: Array[Dictionary]) -> Color:
	var upto := 0
	for seg in p_segments:
		upto += int(seg.get("count", 0))
		if index < upto:
			return TYPE_TINTS.get(seg.get("type_id", &""), FALLBACK_TINT)
	return FALLBACK_TINT


func _track_rect() -> Rect2:
	return Rect2(0.0, (size.y - TRACK_H) * 0.5, maxf(0.0, size.x - LABEL_W), TRACK_H)


## Pure geometry for [method _draw], in track-local pixels (x = 0 at the
## track's left edge). `segments` is one `{x, w, tint}` shaft per arrow, in
## the order the input lists them (never sorted); `w` never exceeds
## [param max_w]. `pitch` is the per-arrow step, `min(track_w / max, max_w +
## gap)`: a sparse volley left-packs rather than stretching. `wave_x` is one
## notch per wave boundary; `arrow_x` is one tick per arrow boundary strictly
## inside the packed span, or empty with `arrows_suppressed` true when
## [method GaugeDensity.ticks_fit] says the pitch is illegible.
static func layout(p_n: int, p_max: int, p_notches: PackedInt32Array, p_segments: Array[Dictionary], track_w: float, max_w: float = INF, gap: float = 0.0) -> Dictionary:
	var out := {
		"segments": [],
		"wave_x": PackedFloat32Array(),
		"arrow_x": PackedFloat32Array(),
		"arrows_suppressed": false,
		"pitch": 0.0,
	}
	if p_max <= 0 or track_w <= 0.0:
		return out
	var px_per := minf(track_w / float(p_max), max_w + gap)
	out["pitch"] = px_per
	var shaft_w := minf(maxf(px_per - gap, 0.0), max_w)
	var x := 0.0
	for seg in p_segments:
		var tint: Color = TYPE_TINTS.get(seg.get("type_id", &""), FALLBACK_TINT)
		for _i in int(seg.get("count", 0)):
			out["segments"].append({"x": x, "w": shaft_w, "tint": tint})
			x += px_per
	for notch in p_notches:
		out["wave_x"].append(px_per * float(notch))
	if GaugeDensity.ticks_fit(p_max, px_per * float(p_max)):
		for i in range(1, p_max):
			out["arrow_x"].append(px_per * float(i))
	else:
		out["arrows_suppressed"] = true
	return out


func _draw() -> void:
	var track := _track_rect()
	draw_rect(track, TRACK_COLOR)
	var lay := layout(n, max_n, notches, segments, track.size.x, max_shaft_width, shaft_gap)
	var pitch: float = lay["pitch"]
	_shaft_layer.queue_redraw()
	if max_n > 0 and _arrow_state.size() > 0:
		var px_per := pitch
		for i in mini(_arrow_state.size(), max_n):
			var state := _arrow_state[i]
			var fired := _arrow_fired[i]
			if state <= 0.0 and fired <= 0.0:
				continue
			var p := paint_slice(state, fired, _slice_tint(i, segments))
			var slice := Rect2(track.position.x + px_per * float(i), track.position.y, px_per, track.size.y)
			if state > 0.0:
				draw_rect(slice, p["lit"] as Color)
			var eaten: float = float(p["fired"]) * track.size.y
			if eaten > 0.0:
				draw_rect(Rect2(slice.position.x, track.end.y - eaten, px_per, eaten), p["dim"] as Color)
	var tick_color := NOTCH_COLOR
	tick_color.a *= 0.5
	var mid_y := track.position.y + track.size.y * 0.5
	for ax: float in lay["arrow_x"]:
		var tx: float = track.position.x + ax
		draw_line(Vector2(tx, mid_y), Vector2(tx, track.end.y), tick_color, 1.0)
	for wx: float in lay["wave_x"]:
		var nx: float = track.position.x + wx
		draw_line(Vector2(nx, track.position.y), Vector2(nx, track.end.y), NOTCH_COLOR, 2.0)
	draw_rect(track, TRACK_EDGE, false, 1.0)
	if _font == null:
		return
	var text := "%d / %d" % [n, max_n] if max_n > 0 else "—"
	var pos := Vector2(track.end.x + 8.0, track.position.y + TRACK_H - 4.0)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 8.0, 12,
			EMPTY_TINT if max_n == 0 else Color.WHITE)


## The shaft layer's `draw`: one 1x1 white texture per shaft, its UV spanning
## the shaft's own width for the cylinder shader; colour rides the vertex
## colour, so the whole bar is one material and one batch.
func _draw_shafts() -> void:
	var track := _track_rect()
	var lay := layout(n, max_n, notches, segments, track.size.x, max_shaft_width, shaft_gap)
	var white := _white()
	for seg: Dictionary in lay["segments"]:
		_shaft_layer.draw_texture_rect(white, Rect2(track.position.x + float(seg["x"]), track.position.y, float(seg["w"]), track.size.y), false, seg["tint"] as Color)


func _white() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


func _n_at(x: float) -> int:
	var track := _track_rect()
	if max_n <= 0 or track.size.x <= 0.0:
		return 0
	var pitch: float = layout(0, max_n, PackedInt32Array(), [] as Array[Dictionary], track.size.x, max_shaft_width, shaft_gap)["pitch"]
	return clampi(ceili((x - track.position.x) / pitch), 0, max_n)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					step_requested.emit(1, mb.shift_pressed)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					step_requested.emit(-1, mb.shift_pressed)
					accept_event()
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				if mb.pressed:
					set_requested.emit(_n_at(mb.position.x))
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		set_requested.emit(_n_at((event as InputEventMouseMotion).position.x))
		accept_event()
