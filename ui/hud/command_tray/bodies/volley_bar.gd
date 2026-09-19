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

var n: int = 0
var max_n: int = 0
## Cumulative wave sizes strictly below max, e.g. 3, 6, 9 for max 11.
var notches: PackedInt32Array = PackedInt32Array()
## `[{type_id, count}]` in roster order, Σ count == n.
var segments: Array[Dictionary] = []

var _font: Font
var _dragging := false


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, TRACK_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()


func set_volley(p_n: int, p_max: int, p_notches: PackedInt32Array, p_segments: Array[Dictionary]) -> void:
	n = p_n
	max_n = p_max
	notches = p_notches
	segments = p_segments
	tooltip_text = "%d / %d arrows · scroll ±1 · Shift+scroll ±wave · M = max" % [n, max_n]
	queue_redraw()


func _track_rect() -> Rect2:
	return Rect2(0.0, (size.y - TRACK_H) * 0.5, maxf(0.0, size.x - LABEL_W), TRACK_H)


func _draw() -> void:
	var track := _track_rect()
	draw_rect(track, TRACK_COLOR)
	if max_n > 0 and track.size.x > 0.0:
		var px_per := track.size.x / float(max_n)
		var x := track.position.x
		for seg in segments:
			var w := px_per * float(int(seg.get("count", 0)))
			var tint: Color = TYPE_TINTS.get(seg.get("type_id", &""), FALLBACK_TINT)
			draw_rect(Rect2(x, track.position.y, w, track.size.y), tint)
			x += w
		for notch in notches:
			var nx := track.position.x + px_per * float(notch)
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
