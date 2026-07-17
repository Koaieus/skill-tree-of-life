@tool
class_name AttributeRadar
extends Control
## Pentagon (promotable to hexagon) attribute radar chart. Plain _draw()
## polygon rendering — no shader needed for flat-shaded native drawing.
## Exposes per-axis hover so the Attributes Panel can drive the
## "hover a row -> tooltip listing what it drives" behavior; this
## component only reports which axis is hovered, it doesn't own tooltips.

signal axis_hovered(index: int)
signal axis_unhovered

@export var axis_labels: Array[String] = ["STR", "DEX", "INT", "WIS", "PER"]:
	set(v):
		axis_labels = v
		queue_redraw()

@export var axis_values: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]:
	set(v):
		axis_values = v
		queue_redraw()

@export var axis_colors: Array[Color] = [
	Color(0.9451, 0.2689, 0.2453, 1), Color(0.3187, 0.7773, 0.4484, 1),
	Color(0.291, 0.5892, 1.0, 1), Color(0.9039, 0.7331, 0.2746, 1),
	Color(0.6935, 0.4045, 0.9676, 1),
]:
	set(v):
		axis_colors = v
		queue_redraw()

## Axis values are normalized against this before plotting.
@export var max_value: float = 60.0:
	set(v):
		max_value = max(0.0001, v)
		queue_redraw()

@export var fill_color: Color = Color(0.82, 0.75, 0.47, 0.14):
	set(v):
		fill_color = v
		queue_redraw()

@export var ring_count: int = 3:
	set(v):
		ring_count = max(1, v)
		queue_redraw()

var _hovered_axis: int = -1

## Half the draw_string width used for axis labels (see LABEL_TEXT_WIDTH) —
## reserved outside the label ring so a label's text box can't spill past
## the Control's rect. Kept as a margin against the Control's half-extent,
## not against _get_radius(), so it doesn't compound with ring/plot sizing.
const LABEL_MARGIN := 22.0
## Total width passed to draw_string for axis labels (HORIZONTAL_ALIGNMENT_CENTER).
const LABEL_TEXT_WIDTH := 40.0
## Visual gap between the plotted ring (_get_radius) and the label ring
## (_get_label_radius) so labels don't crowd the outermost ring line.
const LABEL_RING_GAP := 10.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)

func _get_center() -> Vector2:
	return size * 0.5

## Effective plot radius for rings/polygon/dots/axis-lines. Derived from the
## label ring (see _get_label_radius) minus LABEL_RING_GAP, so the plot never
## grows into space reserved for labels.
func _get_radius() -> float:
	return max(4.0, _get_label_radius() - LABEL_RING_GAP)

## Radius of the ring axis labels are anchored on. Kept LABEL_MARGIN inside
## the Control's half-extent so `label_pos ± LABEL_TEXT_WIDTH/2` (the
## draw_string box, see _draw) never crosses Rect2(Vector2.ZERO, size).
func _get_label_radius() -> float:
	return max(0.0, min(size.x, size.y) * 0.5 - LABEL_MARGIN)

func _axis_point(i: int, frac: float) -> Vector2:
	var n := axis_labels.size()
	var angle := -PI / 2.0 + (TAU / float(n)) * i
	return _get_center() + Vector2(cos(angle), sin(angle)) * _get_radius() * frac

## Anchor for axis label i, on the label ring — outside the plotted radius,
## but bounded so it (plus the draw_string offset applied in _draw) stays
## inside the Control's rect. Extracted so a test can assert the bound
## without needing a live _draw() pass.
func _label_anchor(i: int) -> Vector2:
	var n := axis_labels.size()
	var angle := -PI / 2.0 + (TAU / float(n)) * i
	return _get_center() + Vector2(cos(angle), sin(angle)) * _get_label_radius()

func _draw() -> void:
	var n := axis_labels.size()
	if n < 3:
		return
	var radius := _get_radius()

	for ring in range(1, ring_count + 1):
		var frac := float(ring) / float(ring_count)
		var pts := PackedVector2Array()
		for i in n:
			pts.append(_axis_point(i, frac))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.59, 0.67, 0.82, 0.10), 1.0)

	var center := _get_center()
	for i in n:
		draw_line(center, _axis_point(i, 1.0), Color(0.59, 0.67, 0.82, 0.10), 1.0)

	var data_pts := PackedVector2Array()
	for i in n:
		var frac: float = clamp(axis_values[i] / max_value, 0.0, 1.0) if i < axis_values.size() else 0.0
		data_pts.append(_axis_point(i, frac))
	if data_pts.size() >= 3:
		draw_colored_polygon(data_pts, fill_color)
		var outline := data_pts.duplicate()
		outline.append(outline[0])
		draw_polyline(outline, Color(0.82, 0.72, 0.53, 0.9), 1.6, true)

	for i in n:
		var frac: float = clamp(axis_values[i] / max_value, 0.0, 1.0) if i < axis_values.size() else 0.0
		var col: Color = axis_colors[i] if i < axis_colors.size() else Color.WHITE
		var dot_radius := 5.0 if i == _hovered_axis else 3.2
		draw_circle(_axis_point(i, frac), dot_radius, col)

	for i in n:
		var label_pos := _label_anchor(i)
		var col: Color = axis_colors[i] if i < axis_colors.size() else Color.WHITE
		draw_string(ThemeDB.fallback_font, label_pos - Vector2(LABEL_TEXT_WIDTH * 0.5, -4), axis_labels[i], HORIZONTAL_ALIGNMENT_CENTER, LABEL_TEXT_WIDTH, 12, col)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var new_hover := _hit_test_axis(event.position)
		if new_hover != _hovered_axis:
			_hovered_axis = new_hover
			queue_redraw()
			if _hovered_axis >= 0:
				axis_hovered.emit(_hovered_axis)
			else:
				axis_unhovered.emit()

func _hit_test_axis(pos: Vector2) -> int:
	var n := axis_labels.size()
	var center := _get_center()
	var to_pos := pos - center
	if to_pos.length() < 6.0:
		return -1
	var angle := to_pos.angle() + PI / 2.0
	if angle < 0.0:
		angle += TAU
	var step := TAU / float(n)
	var idx := int(round(angle / step)) % n
	var closest := _axis_point(idx, 1.0)
	if pos.distance_to(closest) > _get_radius() * 0.5:
		return -1
	return idx
