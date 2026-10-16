@tool
class_name StatusOverlay
extends Control

## Every status readout on a bar: the projected-damage segment and the icon
## row, for ONE host's rows. Composed as a full-rect child of the bar it
## annotates; the bar owns the wiring.
##
## [b]Host.[/b] [method bind] takes a [NodeCombat] or an [EntityCombat] (both
## answer `get_statuses()` and `projected_status_damage()`) plus the signal that
## announces a row change ([signal SkillNode.statuses_changed] /
## [signal Entity.statuses_changed]). A node bar binds its node, a core bar the
## entity — two overlays, never merged.
##
## [b]Fill.[/b] The bar pushes the fill it is DRAWING through [method set_fill]
## (its animated `value`, not the pool), so the band stays glued to the fill tip
## while a damage tween runs.
##
## [b]Model, then draw.[/b] [method refresh] rebuilds [member segments] and
## [member icons] from the live rows; `_draw` only paints them. A consumer (or a
## later readout) adds segments to the model, never draws status on a bar
## outside this scene. Zero rows → hidden, so a clean node costs no `_draw`.
## Colour is the row identity's `tint`, unlifted; icons share their textures
## and tint through `modulate`, so the row batches.

## One band of the projected-damage segment: one damaging row, stacked back
## from the fill tip in row order.
class Segment:
	var id: StringName
	var rect: Rect2
	var color: Color

## One icon of the row. `count` is the stack count, `-1` when the def's stacks
## do not matter ([member StatusDef.display_max] ≤ 1).
class IconEntry:
	var id: StringName
	var texture: Texture2D
	var count: int = -1
	var rect: Rect2

## Edge of one icon, px. Tentative, easy to change.
@export_range(4.0, 32.0, 1.0) var icon_size: float = 10.0:
	set(v):
		icon_size = v
		refresh()
## Gap between icons, and between the row and the bar, px. Tentative.
@export_range(0.0, 8.0, 0.5) var icon_gap: float = 2.0:
	set(v):
		icon_gap = v
		refresh()

## The model `_draw` paints. Read-only for callers.
var segments: Array[Segment] = []
var icons: Array[IconEntry] = []
## The corruption layer (node hosts only): one pending chunk per stack, stacked
## back from the tip after the bands; the ghost (N+1)th chunk while critical
## (empty otherwise); one blip per stack above the icon row.
var chunks: Array[Rect2] = []
var ghost: Rect2 = Rect2()
var blips: Array[Rect2] = []
## `N == T − 1`: one more stack, or one lost degree, cashes the chunks in.
var critical: bool = false

var _host: Object = null
var _fill_value: float = 0.0
var _fill_max: float = 0.0
var _subs := SubBag.new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		refresh()


## Point at [param host]'s rows (null detaches). [param changed] fires on every
## apply / tick / remove of those rows.
func bind(host: Object, changed: Signal = Signal()) -> void:
	_subs.clear()
	_host = host
	if _host != null and not changed.is_null():
		_subs.on(changed, refresh)
	refresh()


## The fill the hosting bar is drawing right now, in its own units.
func set_fill(fill_value: float, fill_max: float) -> void:
	_fill_value = fill_value
	_fill_max = fill_max
	refresh()


func has_rows() -> bool:
	return not _rows().is_empty()


## Rebuild the model from the live rows and repaint.
func refresh() -> void:
	segments.clear()
	icons.clear()
	var rows := _rows()
	visible = not rows.is_empty()
	if rows.is_empty():
		return
	_build_segments(rows)
	_build_icons(rows)
	queue_redraw()


func _rows() -> Array[NodeStatus]:
	if _host == null or not is_instance_valid(_host):
		return []
	return _host.get_statuses()


func _build_segments(rows: Array[NodeStatus]) -> void:
	if _fill_max <= 0.0:
		return
	var tip := clampf(_fill_value / _fill_max, 0.0, 1.0) * size.x
	for row in rows:
		var dmg: float = row.def.projected_damage(_host, row.power)
		if dmg <= 0.0 or tip <= 0.0:
			continue
		var w := minf(dmg / _fill_max * size.x, tip)
		var s := Segment.new()
		s.id = row.def.id
		s.color = row.def.tint
		s.rect = Rect2(tip - w, 0.0, w, size.y)
		segments.append(s)
		tip -= w


func _build_icons(rows: Array[NodeStatus]) -> void:
	var x := 0.0
	var y := -icon_size - icon_gap
	for row in rows:
		var tex: Texture2D = row.def.icon
		if tex == null:
			continue
		var e := IconEntry.new()
		e.id = row.def.id
		e.texture = tex
		e.count = row.power if row.def.display_max > 1.0 else -1
		e.rect = Rect2(x, y, icon_size, icon_size)
		icons.append(e)
		x += icon_size + icon_gap


func _draw() -> void:
	for s in segments:
		draw_rect(s.rect, s.color)
	var font := ThemeDB.fallback_font
	var font_size := maxi(int(icon_size * 0.8), 6)
	for e in icons:
		draw_texture_rect(e.texture, e.rect, false)
		if e.count >= 0:
			draw_string_outline(font, e.rect.end + Vector2(-font_size * 0.5, 0.0), str(e.count),
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color.BLACK)
			draw_string(font, e.rect.end + Vector2(-font_size * 0.5, 0.0), str(e.count),
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
