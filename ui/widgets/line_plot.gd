@tool
class_name LinePlot
extends Control

## A minimal reusable line chart: N value series drawn auto-scaled into this
## Control's rect, with a horizontal zero line. Knows nothing of what it plots.
## Every series shares one x-domain (index i sits at the same x on every line,
## spread over the longest series); y spans the min..max of all series, always
## including 0. A series of fewer than 2 points draws nothing; an empty plot
## draws nothing at all. Size and anchors are the Control's own.

## Stroke width of each series line, in pixels.
@export_range(0.5, 8.0, 0.5) var line_width: float = 2.0:
	set(v):
		line_width = v
		queue_redraw()
## Colour of the y = 0 reference line.
@export var zero_line_color: Color = Color(1, 1, 1, 0.35):
	set(v):
		zero_line_color = v
		queue_redraw()
## Stroke width of the zero line, in pixels; 0 hides it.
@export_range(0.0, 4.0, 0.5) var zero_line_width: float = 1.0:
	set(v):
		zero_line_width = v
		queue_redraw()
## Inset of the plotting area from every edge, in pixels.
@export_range(0.0, 32.0, 1.0) var padding: float = 4.0:
	set(v):
		padding = v
		queue_redraw()
## Anti-aliased strokes.
@export var antialiased: bool = true:
	set(v):
		antialiased = v
		queue_redraw()

var _series: Array[PackedFloat32Array] = []
var _colors: PackedColorArray = PackedColorArray()


## Replaces every series; colors[i] paints series i (white when missing).
func set_series(series: Array[PackedFloat32Array], colors: PackedColorArray) -> void:
	_series = series.duplicate()
	_colors = colors.duplicate()
	queue_redraw()


## The y-domain of [param series]: min and max over every series of 2+ points,
## widened to include 0, and widened by 1 around a flat range so it never
## divides by zero. Vector2(x = min, y = max).
static func value_range(series: Array[PackedFloat32Array]) -> Vector2:
	var lo := 0.0
	var hi := 0.0
	for values in series:
		if values.size() < 2:
			continue
		for v in values:
			lo = minf(lo, v)
			hi = maxf(hi, v)
	if is_equal_approx(lo, hi):
		lo -= 0.5
		hi += 0.5
	return Vector2(lo, hi)


## The number of x slots shared by every series: the longest series' length.
static func x_count(series: Array[PackedFloat32Array]) -> int:
	var n := 0
	for values in series:
		n = maxi(n, values.size())
	return n


## The y pixel of [param value] in [param rect] for domain [vmin, vmax]:
## vmax maps to the rect's top, vmin to its bottom.
static func y_of(value: float, rect: Rect2, vmin: float, vmax: float) -> float:
	var t := inverse_lerp(vmin, vmax, value)
	return rect.position.y + rect.size.y * (1.0 - t)


## [param values] as points in [param rect], index i at x = i / (count - 1)
## across the rect. Empty for fewer than 2 values or count < 2.
static func to_points(values: PackedFloat32Array, rect: Rect2, vmin: float, vmax: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if values.size() < 2 or count < 2:
		return points
	var step := rect.size.x / float(count - 1)
	points.resize(values.size())
	for i in values.size():
		points[i] = Vector2(rect.position.x + step * i, y_of(values[i], rect, vmin, vmax))
	return points


func _draw() -> void:
	var count := x_count(_series)
	if count < 2:
		return
	var rect := Rect2(Vector2.ZERO, size).grow(-padding)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var domain := value_range(_series)
	var lines: Array[PackedVector2Array] = []
	for values in _series:
		lines.append(to_points(values, rect, domain.x, domain.y, count))
	if lines.all(func(p: PackedVector2Array) -> bool: return p.is_empty()):
		return
	if zero_line_width > 0.0:
		var zy := y_of(0.0, rect, domain.x, domain.y)
		draw_line(Vector2(rect.position.x, zy), Vector2(rect.end.x, zy), zero_line_color, zero_line_width, antialiased)
	for i in lines.size():
		if lines[i].is_empty():
			continue
		var color := _colors[i] if i < _colors.size() else Color.WHITE
		draw_polyline(lines[i], color, line_width, antialiased)
