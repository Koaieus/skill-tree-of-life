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

var n: int = 0
var max_n: int = 0
## Cumulative wave sizes strictly below max, e.g. 3, 6, 9 for max 11.
var notches: PackedInt32Array = PackedInt32Array()
## `[{type_id, count}]` in roster order, Σ count == n.
var segments: Array[Dictionary] = []

var _font: Font
var _dragging := false

## Per-arrow charge strip of the launched volley, 0 = normal, 1 = lit; the
## painted value, written by the placement tweens.
var _arrow_state: PackedFloat32Array = PackedFloat32Array()
## Per-arrow drain strip, 0..1 = how far the dim has eaten the slice upward.
var _arrow_fired: PackedFloat32Array = PackedFloat32Array()
## What the tweens aim at — the schedule, readable without a frame.
var arrow_state_target: PackedFloat32Array = PackedFloat32Array()
var arrow_fired_target: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, TRACK_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()


func set_volley(p_n: int, p_max: int, p_notches: PackedInt32Array, p_segments: Array[Dictionary], hold: bool = false) -> void:
	n = p_n
	max_n = p_max
	notches = p_notches
	segments = p_segments
	tooltip_text = "%d / %d arrows · scroll ±1 · Shift+scroll ±wave · M = max" % [n, max_n]
	queue_redraw()


func on_arrow_placed(_index: int, _total: int) -> void:
	pass


func on_arrow_released(_index: int, _total: int) -> void:
	pass


## Pure: the colours of one arrow slice for a charge `state` and a drain
## `fired` fraction.
static func paint_slice(_state: float, _fired: float, tint: Color) -> Dictionary:
	return {"lit": tint, "dim": tint, "fired": 0.0}


func _track_rect() -> Rect2:
	return Rect2(0.0, (size.y - TRACK_H) * 0.5, maxf(0.0, size.x - LABEL_W), TRACK_H)


## Pure geometry for [method _draw], in track-local pixels (x = 0 at the
## track's left edge). `segments` are `{x, w, tint}` rects tiling the filled
## width in roster order; `wave_x` is one notch per wave boundary; `arrow_x`
## is one tick per arrow boundary strictly inside the track, or empty with
## `arrows_suppressed` true when [method GaugeDensity.ticks_fit] says the
## pitch is illegible. A sibling paints per-arrow state on top of this shape.
static func layout(p_n: int, p_max: int, p_notches: PackedInt32Array, p_segments: Array[Dictionary], track_w: float) -> Dictionary:
	var out := {
		"segments": [],
		"wave_x": PackedFloat32Array(),
		"arrow_x": PackedFloat32Array(),
		"arrows_suppressed": false,
	}
	if p_max <= 0 or track_w <= 0.0:
		return out
	var px_per := track_w / float(p_max)
	var x := 0.0
	for seg in p_segments:
		var w := px_per * float(int(seg.get("count", 0)))
		var tint: Color = TYPE_TINTS.get(seg.get("type_id", &""), FALLBACK_TINT)
		out["segments"].append({"x": x, "w": w, "tint": tint})
		x += w
	for notch in p_notches:
		out["wave_x"].append(px_per * float(notch))
	if GaugeDensity.ticks_fit(p_max, track_w):
		for i in range(1, p_max):
			out["arrow_x"].append(px_per * float(i))
	else:
		out["arrows_suppressed"] = true
	return out


func _draw() -> void:
	var track := _track_rect()
	draw_rect(track, TRACK_COLOR)
	var lay := layout(n, max_n, notches, segments, track.size.x)
	for seg: Dictionary in lay["segments"]:
		draw_rect(Rect2(track.position.x + float(seg["x"]), track.position.y, float(seg["w"]), track.size.y), seg["tint"] as Color)
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


func _n_at(x: float) -> int:
	var track := _track_rect()
	if max_n <= 0 or track.size.x <= 0.0:
		return 0
	return clampi(ceili((x - track.position.x) / track.size.x * float(max_n)), 0, max_n)


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
