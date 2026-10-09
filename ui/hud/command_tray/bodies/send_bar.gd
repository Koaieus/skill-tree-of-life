@tool
class_name SendBar
extends Control

## A vertical send bar. The inner fill is the share of the pile going into this
## volley ([member value] of [member stock]), rising from the bottom; its border
## glows up the sides by the stock's magnitude, one segment per entry of
## [member border_decades] (log scale). Fed numbers only; it never sets its own
## [member value] — it asks via [signal value_requested] and the host decides.

## Click/drag at a height, or scroll ±1; always clamped to 0..[member stock].
signal value_requested(n: int)

@export var stock: int = 0:
	set(v):
		stock = maxi(v, 0)
		queue_redraw()
@export var value: int = 0:
	set(v):
		value = v
		queue_redraw()
@export var tint: Color = Color.WHITE:
	set(v):
		tint = v
		queue_redraw()
## Lower bounds of the border segments, ascending; the last spans one decade.
@export var border_decades: PackedInt32Array = [1, 10, 100]:
	set(v):
		border_decades = v
		queue_redraw()
## The lit border's glow, a named tier — never a float.
@export var glow_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(v):
		glow_tier = v
		queue_redraw()
@export_range(1.0, 6.0) var border_px: float = 2.0:
	set(v):
		border_px = v
		queue_redraw()
## Share of a segment shown the moment it lights, so a lit segment is never invisible.
@export_range(0.0, 1.0) var segment_floor: float = 0.15:
	set(v):
		segment_floor = v
		queue_redraw()
## How far the unlit track and border sit below [member tint], as a darkening.
@export_range(0.0, 1.0) var dim: float = 0.7:
	set(v):
		dim = v
		queue_redraw()


## The amount at a local y: its fraction FROM THE BOTTOM of the bar, times stock.
static func value_at(local_y: float, height: float, stock: int) -> int:
	if height <= 0.0 or stock <= 0:
		return 0
	return roundi(clampf(1.0 - local_y / height, 0.0, 1.0) * stock)


## Border segments lit for a stock: 0 at nothing, then one per bound reached.
static func lit_thirds(stock: int, border_decades: PackedInt32Array) -> int:
	if stock <= 0:
		return 0
	var lit := 0
	for d in border_decades:
		if stock >= d:
			lit += 1
	return lit


## Height share (0..1) of the lit border: whole segments below, plus the current
## segment's log progress lifted by [param floor_share].
static func border_fill(stock: int, border_decades: PackedInt32Array, floor_share: float) -> float:
	var lit := lit_thirds(stock, border_decades)
	if lit == 0:
		return 0.0
	var lo := float(maxi(border_decades[lit - 1], 1))
	var hi := float(border_decades[lit]) if lit < border_decades.size() else lo * 10.0
	var t := clampf(log(stock / lo) / log(maxf(hi / lo, 1.0001)), 0.0, 1.0)
	return (lit - 1 + lerpf(floor_share, 1.0, t)) / border_decades.size()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_request(value_at(mb.position.y, size.y, stock))
			MOUSE_BUTTON_WHEEL_UP:
				_request(value + 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_request(value - 1)
			_:
				return
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_request(value_at(mm.position.y, size.y, stock))
		accept_event()


func _request(n: int) -> void:
	value_requested.emit(clampi(n, 0, stock))


func _draw() -> void:
	var w := size.x
	var h := size.y
	var b := border_px
	var dark := tint.darkened(dim)
	var inner := Rect2(b, b, w - 2.0 * b, h - 2.0 * b)
	draw_rect(inner, dark.darkened(0.5))
	var share := 0.0 if stock <= 0 else clampf(float(value) / stock, 0.0, 1.0)
	if share > 0.0:
		var fh := inner.size.y * share
		draw_rect(Rect2(inner.position.x, inner.end.y - fh, inner.size.x, fh), tint)
	# Dim frame, then the lit bottom + sides over it.
	draw_rect(Rect2(b * 0.5, b * 0.5, w - b, h - b), dark, false, b)
	var fill := border_fill(stock, border_decades, segment_floor)
	if fill <= 0.0:
		return
	var glow := Emissive.at(tint, Emissive.stops(glow_tier))
	var y_top := h - h * fill
	var x0 := b * 0.5
	var x1 := w - b * 0.5
	var yb := h - b * 0.5
	draw_polyline(PackedVector2Array([Vector2(x0, y_top), Vector2(x0, yb), Vector2(x1, yb), Vector2(x1, y_top)]), glow, b)
