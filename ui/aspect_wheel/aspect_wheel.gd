@tool
class_name AspectWheel
extends Control

## A radial chooser: one wedge per [AspectWheelEntry], in the order bound (the
## caller passes roster order so an aspect keeps its angle). A wedge's fill
## radius grows with its value, the tips are joined AttributeRadar-style, and
## the hub names the hovered wedge. Pure view: entries in, signals out.
##
## Angles are degrees clockwise from 12 o'clock. The whole wedge (hub to
## [member radius_px]) is the hit target, not just its filled part.

## The pointer moved onto a wedge, or off every wedge (`&""`).
signal hovered(id: StringName)
## Left-click on a pickable wedge.
signal picked(id: StringName)
## Right-click or `ui_cancel`.
signal dismissed

## Outer radius of every wedge. Tentative.
@export_range(32.0, 256.0, 1.0) var radius_px: float = 96.0:
	set(v):
		radius_px = v
		update_minimum_size()
		queue_redraw()
## Radius of the hub — the dead centre that shows the hovered wedge's text. Tentative.
@export_range(0.0, 128.0, 1.0) var inner_radius_px: float = 28.0:
	set(v):
		inner_radius_px = v
		queue_redraw()
## Empty arc between neighbouring wedges. Tentative.
@export_range(0.0, 20.0, 0.5) var wedge_gap_deg: float = 3.0:
	set(v):
		wedge_gap_deg = v
		queue_redraw()
## Fill fraction of the hub-to-rim span for the smallest value, so a wedge
## holding 1 stays visible. Tentative.
@export_range(0.0, 1.0, 0.01) var min_fill: float = 0.15:
	set(v):
		min_fill = v
		queue_redraw()
## Edge of each wedge's identity badge. Tentative.
@export_range(8, 64) var badge_px: int = 20:
	set(v):
		badge_px = v
		queue_redraw()
## Alpha of a wedge's filled area (hovered wedges draw opaque-er). Tentative.
@export_range(0.0, 1.0, 0.01) var fill_alpha: float = 0.35:
	set(v):
		fill_alpha = v
		queue_redraw()
## How lit tints, badges and values read.
@export var emissive_tier: Emissive.Tier = Emissive.Tier.LABEL:
	set(v):
		emissive_tier = v
		queue_redraw()
## How lit the hovered wedge reads.
@export var hover_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(v):
		hover_tier = v
		queue_redraw()

## A display, not a chooser: hover still names a wedge, but nothing picks or
## dismisses, clicks and `ui_cancel` fall through to whatever is behind it,
## and the per-wedge value digits are dropped (the fill is the value).
@export var read_only: bool = false:
	set(v):
		read_only = v
		queue_redraw()

const _ARC_STEPS_PER_TURN := 96

var _entries: Array[AspectWheelEntry] = []
var _hovered_id: StringName = &""


func _ready() -> void:
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


func _get_minimum_size() -> Vector2:
	return Vector2.ONE * radius_px * 2.0


## Replace the wedges. Clears the hover without emitting.
func bind(entries: Array[AspectWheelEntry]) -> void:
	_entries = entries.duplicate()
	_hovered_id = &""
	queue_redraw()


func entry_count() -> int:
	return _entries.size()


## `Vector2(start, end)` of wedge `index`, in degrees clockwise from 12
## o'clock: `[i, i+1) × 360/N` shrunk by half the gap at each side.
func wedge_span(index: int) -> Vector2:
	var step := _step_deg()
	var half_gap := _half_gap_deg()
	return Vector2(index * step + half_gap, (index + 1) * step - half_gap)


## The id of the wedge under `local_pos`; `&""` in the hub, a gap or past the rim.
func wedge_at(local_pos: Vector2) -> StringName:
	var index := _index_at(local_pos)
	return _entries[index].id if index >= 0 else &""


## Filled radius of wedge `index`: `lerp(min_fill, 1, value / max value)` of
## the hub-to-rim span, measured from the hub — so the floor stays outside the
## hub and is never below `min_fill × radius_px`.
func fill_radius(index: int) -> float:
	if index < 0 or index >= _entries.size():
		return inner_radius_px
	var top := 1
	for entry in _entries:
		top = maxi(top, entry.value)
	var frac := lerpf(min_fill, 1.0, clampf(float(_entries[index].value) / top, 0.0, 1.0))
	return inner_radius_px + (radius_px - inner_radius_px) * frac


func _step_deg() -> float:
	return 360.0 / maxi(1, _entries.size())


func _half_gap_deg() -> float:
	return minf(wedge_gap_deg, _step_deg() * 0.5) * 0.5


func _center() -> Vector2:
	return size * 0.5


## Wedge index under a local point, or -1.
func _index_at(local_pos: Vector2) -> int:
	if _entries.is_empty():
		return -1
	var d := local_pos - _center()
	var r := d.length()
	if r < inner_radius_px or r > radius_px:
		return -1
	var deg := fposmod(rad_to_deg(d.angle()) + 90.0, 360.0)
	var step := _step_deg()
	var index := mini(int(deg / step), _entries.size() - 1)
	var offset := deg - index * step
	var half_gap := _half_gap_deg()
	if offset < half_gap or offset > step - half_gap:
		return -1
	return index


func _dir(deg: float) -> Vector2:
	var a := deg_to_rad(deg) - PI / 2.0
	return Vector2(cos(a), sin(a))


func _entry(id: StringName) -> AspectWheelEntry:
	for entry in _entries:
		if entry.id == id:
			return entry
	return null


# ── Input ────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hovered(wedge_at(event.position))
	elif read_only:
		return
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			dismissed.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var entry := _entry(wedge_at(event.position))
			if entry != null and entry.is_pickable():
				accept_event()
				picked.emit(entry.id)


func _unhandled_input(event: InputEvent) -> void:
	if not read_only and is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		dismissed.emit()


func _on_mouse_exited() -> void:
	_set_hovered(&"")


func _set_hovered(id: StringName) -> void:
	if id == _hovered_id:
		return
	_hovered_id = id
	queue_redraw()
	hovered.emit(id)


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var center := _center()
	var n := _entries.size()
	var grey := Emissive.neutral(Emissive.stops(Emissive.Tier.INERT))
	draw_arc(center, inner_radius_px, 0.0, TAU, _ARC_STEPS_PER_TURN, Color(grey, 0.5), 1.0, true)
	if n == 0:
		return
	var font := get_theme_default_font()
	var tips := PackedVector2Array()
	for i in n:
		var entry := _entries[i]
		var span := wedge_span(i)
		var mid := (span.x + span.y) * 0.5
		var is_hover := entry.id == _hovered_id
		var tint := _tint(entry, is_hover)
		var fill := fill_radius(i)
		# Rim track, then the filled sector.
		draw_colored_polygon(_sector(center, span, inner_radius_px, radius_px), Color(tint, 0.06))
		draw_colored_polygon(_sector(center, span, inner_radius_px, fill), Color(tint, minf(1.0, fill_alpha * (1.6 if is_hover else 1.0))))
		draw_polyline(_arc_points(center, span, fill), tint, 1.5 if is_hover else 1.0, true)
		tips.append(center + _dir(mid) * fill)
		# Badge at the wedge's centroid, value outboard of it.
		var badge_r := (inner_radius_px + radius_px) * 0.5
		var badge_pos := center + _dir(mid) * badge_r
		var badge := IdentityBadge.composite(entry.identity, badge_px)
		if badge != null:
			draw_texture_rect(badge, Rect2(badge_pos - Vector2.ONE * badge_px * 0.5, Vector2.ONE * badge_px), false, tint)
		var value_pos := center + _dir(mid) * (badge_r + badge_px * 0.5 + (radius_px - badge_r - badge_px * 0.5) * 0.5)
		if not read_only:
			_draw_centered(font, value_pos, str(entry.value), 12, tint)
		if not entry.is_pickable():
			draw_line(center + _dir(span.x) * inner_radius_px, center + _dir(span.y) * radius_px, Color(grey, 0.8), 1.5, true)
		elif entry.checked:
			_draw_check(center + _dir(mid) * (radius_px - 6.0), tint)
	if n >= 3:
		tips.append(tips[0])
		draw_polyline(tips, Color(Emissive.neutral(Emissive.stops(emissive_tier)), 0.25), 1.0, true)
	var hovered_entry := _entry(_hovered_id)
	if hovered_entry != null:
		var text := hovered_entry.hub_text if hovered_entry.is_pickable() else hovered_entry.disabled_reason
		_draw_centered(font, center, text, 11, _tint(hovered_entry, true), inner_radius_px * 1.8)


func _tint(entry: AspectWheelEntry, is_hover: bool) -> Color:
	if not entry.is_pickable():
		return Color(Emissive.neutral(Emissive.stops(Emissive.Tier.INERT)), 0.45)
	var hue := entry.identity.tint if entry.identity != null else Emissive.NEUTRAL
	return Emissive.at(hue, Emissive.stops(hover_tier if is_hover else emissive_tier))


func _arc_points(center: Vector2, span: Vector2, r: float) -> PackedVector2Array:
	var steps := maxi(2, ceili((span.y - span.x) / 360.0 * _ARC_STEPS_PER_TURN))
	var out := PackedVector2Array()
	for s in steps + 1:
		out.append(center + _dir(lerpf(span.x, span.y, float(s) / steps)) * r)
	return out


func _sector(center: Vector2, span: Vector2, r0: float, r1: float) -> PackedVector2Array:
	var outer := _arc_points(center, span, r1)
	var inner := _arc_points(center, span, r0)
	inner.reverse()
	outer.append_array(inner)
	return outer


func _draw_centered(font: Font, at: Vector2, text: String, font_size: int, color: Color, width: float = -1.0) -> void:
	if text.is_empty():
		return
	var w := width if width > 0.0 else font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := at + Vector2(-w * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)


func _draw_check(at: Vector2, color: Color) -> void:
	draw_polyline(PackedVector2Array([at + Vector2(-4, 0), at + Vector2(-1, 3), at + Vector2(4, -3)]), color, 1.5, true)
