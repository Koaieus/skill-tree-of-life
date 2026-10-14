@tool
class_name InfusionSocket
extends Control

## One infusion socket of an [InfusionSockets] arc, housed in the aspect badge's
## own frame ([BadgeFrames], so a socket reads as an empty aspect chip), in one
## of three states: [b]empty[/b] — a grey frame; [b]filled[/b] — the frame
## washed in the aspect's tint with its icon inside, the tinted edge tracing
## points / held of the perimeter, and the exchange line under it;
## [b]locked[/b] — a dim ghost labelled with the INT that unlocks it. Pure view: the arc paints
## it and routes its two signals; it never touches the plan.

## Left-click on an owned socket.
signal toggled(index: int)
## Right-click on a filled socket.
signal cleared(index: int)
## Left-click on a locked ghost; it has already flashed its threshold label.
signal locked_tapped(index: int)

enum State { EMPTY, FILLED, LOCKED }

## Edge of the ring. Tentative.
@export_range(16, 96, 1, "suffix:px") var socket_px: int = 44:
	set(v):
		socket_px = v
		update_minimum_size()
		queue_redraw()
## Height reserved under the ring for the exchange line. Tentative.
@export_range(0, 32, 1, "suffix:px") var line_px: int = 14:
	set(v):
		line_px = v
		update_minimum_size()
		queue_redraw()
## Alpha of a locked ghost. Tentative.
@export_range(0.0, 1.0, 0.05) var ghost_alpha: float = 0.35:
	set(v):
		ghost_alpha = v
		queue_redraw()
## Alpha of a locked ghost's label: the ring stays dim, the threshold stays legible.
@export_range(0.0, 1.0, 0.05) var ghost_label_alpha: float = 0.7:
	set(v):
		ghost_label_alpha = v
		queue_redraw()
## Alpha of the recessed fill inside the frame: a locked ghost's, then an owned socket's.
@export_range(0.0, 1.0, 0.01) var disc_alpha_locked: float = 0.1:
	set(v):
		disc_alpha_locked = v
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var disc_alpha_open: float = 0.22:
	set(v):
		disc_alpha_open = v
		queue_redraw()
## Alpha of a filled socket's tint wash inside the frame.
@export_range(0.0, 1.0, 0.01) var fill_alpha_filled: float = 0.3:
	set(v):
		fill_alpha_filled = v
		queue_redraw()
## The icon's size as a fraction of the socket.
@export_range(0.2, 1.0, 0.01) var glyph_scale: float = 0.62:
	set(v):
		glyph_scale = v
		queue_redraw()
## Seconds a tapped ghost's label takes to fade from full back to its resting alpha.
@export_range(0.1, 3.0, 0.1, "suffix:s") var flash_seconds: float = 0.8
## How lit a filled socket's tint reads.
@export var emissive_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(v):
		emissive_tier = v
		queue_redraw()

const _RING_WIDTH := 2.0
const _FONT_PX := 10

## Its position on the arc; what the signals report.
var index: int = 0
var state: State = State.EMPTY
## Its aspect chooser is open.
var is_open: bool = false:
	set(v):
		if v != is_open:
			is_open = v
			queue_redraw()

var _identity: Identity = null
var _fill: float = 0.0
var _line: String = ""
## Extra alpha of the ghost label above its resting alpha, 1 at the tap, 0 at rest.
var _flash: float = 0.0:
	set(v):
		_flash = v
		queue_redraw()
var _flash_tween: Tween = null
var _hint: String = ""


func _get_minimum_size() -> Vector2:
	return Vector2(socket_px, socket_px + line_px)


func show_empty() -> void:
	_paint(State.EMPTY, null, 0.0, "")


## [param points] of [param held] socketed, reading [param line].
func show_filled(identity: Identity, points: int, held: int, line: String) -> void:
	_paint(State.FILLED, identity, clampf(float(points) / maxf(held, 1.0), 0.0, 1.0), line)


## A ghost labelled [param label] (e.g. "INT 1000").
func show_locked(label: String) -> void:
	_paint(State.LOCKED, null, 0.0, label)


## The text under the ring: the exchange line when filled, the unlock label when locked.
func line_text() -> String:
	return _line


func _paint(p_state: State, identity: Identity, fill: float, line: String) -> void:
	state = p_state
	_identity = identity
	_fill = fill
	_line = line
	tooltip_text = _tooltip()
	mouse_default_cursor_shape = CURSOR_ARROW if state == State.LOCKED else CURSOR_POINTING_HAND
	queue_redraw()


func _tooltip() -> String:
	match state:
		State.LOCKED:
			return "Another infusion socket at %s" % _line
		State.FILLED:
			return "%s — click to change, right-click to empty" % _line
	return "Click to socket an aspect"


## Say [param text] under the ring for [member flash_seconds], fading out.
func flash_hint(text: String) -> void:
	_hint = text
	flash_label()


## The last hint flashed.
func hint_text() -> String:
	return _hint


## Fade the label from full alpha to its resting alpha; a re-tap restarts it.
func flash_label() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_flash = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, ^"_flash", 0.0, flash_seconds)


## The locked label's current alpha.
func label_alpha() -> float:
	return lerpf(ghost_label_alpha, 1.0, _flash)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if state == State.LOCKED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			flash_label()
			locked_tapped.emit(index)
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		toggled.emit(index)
	elif event.button_index == MOUSE_BUTTON_RIGHT and state == State.FILLED:
		accept_event()
		cleared.emit(index)


func _draw() -> void:
	var r := socket_px * 0.5 - _RING_WIDTH
	var center := Vector2(size.x * 0.5, socket_px * 0.5)
	var grey := Emissive.neutral(Emissive.stops(Emissive.Tier.INERT))
	var tint := grey
	if state == State.FILLED and _identity != null:
		tint = Emissive.at(_identity.tint, Emissive.stops(emissive_tier))
	var track_alpha := ghost_alpha if state == State.LOCKED else (0.9 if is_open else 0.5)
	var frame := BadgeFrames.shared().frame_for(Identity.Kind.ASPECT).vertices(center, r)
	var loop := frame.duplicate()
	loop.append(frame[0])
	draw_colored_polygon(frame, Color(grey, disc_alpha_locked if state == State.LOCKED else disc_alpha_open))
	if state == State.FILLED:
		draw_colored_polygon(frame, Color(tint, fill_alpha_filled))
	draw_polyline(loop, Color(grey, track_alpha), _RING_WIDTH, true)
	if state == State.FILLED:
		if _fill > 0.0:
			draw_polyline(perimeter_run(frame, _fill), tint, _RING_WIDTH, true)
		var glyph_px := int(socket_px * glyph_scale)
		var glyph := IdentityBadge.glyph(_identity, glyph_px)
		if glyph != null:
			draw_texture_rect(glyph, Rect2(center - Vector2.ONE * glyph_px * 0.5, Vector2.ONE * glyph_px), false, tint)
	var hinting := state != State.LOCKED and not _hint.is_empty() and _flash > 0.0
	var line := _hint if hinting else _line
	if line.is_empty() or line_px <= 0:
		return
	var font := get_theme_default_font()
	var text_color := Color(grey, label_alpha()) if state == State.LOCKED else Color(tint, 0.9)
	if hinting:
		text_color = Color(grey, _flash)
	var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_PX).x
	var at := Vector2(size.x * 0.5 - width * 0.5, socket_px + line_px - 2.0)
	draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_PX, text_color)



## The run along closed polygon [param vertices] (in screen order, clockwise
## with y down) covering [param fraction] of its perimeter, from the midpoint of
## its topmost edge; empty at 0, the whole closed loop at 1.
static func perimeter_run(vertices: PackedVector2Array, fraction: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := vertices.size()
	if n < 2 or fraction <= 0.0:
		return out
	var top := 0
	for i in n:
		if (vertices[i] + vertices[(i + 1) % n]).y < (vertices[top] + vertices[(top + 1) % n]).y:
			top = i
	var perimeter := 0.0
	for i in n:
		perimeter += vertices[i].distance_to(vertices[(i + 1) % n])
	var left := perimeter * minf(fraction, 1.0)
	var at := (vertices[top] + vertices[(top + 1) % n]) * 0.5
	out.append(at)
	var k := (top + 1) % n
	for _step in n + 1:
		var next := vertices[k]
		var leg := at.distance_to(next)
		if leg >= left:
			out.append(at.move_toward(next, left))
			return out
		left -= leg
		out.append(next)
		at = next
		k = (k + 1) % n
	return out
