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

## Per-axis label + color (#241). Drive it via [method configure] rather than
## poking parallel arrays. Plotted values are separate runtime state — see
## [member _values] / [method set_value].
## Colours come from each [StatDef]'s `tint_color` via [method AxisSpec.for_stat]
## — never literals here. This default set only feeds the editor preview; both
## live callers ([AttributesPanel], [OwnerPanel]) replace it via [method configure].
@export var axes: Array[AxisSpec] = [
	AxisSpec.for_stat(&"strength"),
	AxisSpec.for_stat(&"dexterity"),
	AxisSpec.for_stat(&"intelligence"),
	AxisSpec.for_stat(&"constitution"),
	AxisSpec.for_stat(&"wisdom"),
	AxisSpec.for_stat(&"perception"),
]:
	set(v):
		axes = v
		_resize_values()
		queue_redraw()

## Plotted value per axis, normalized via [method _value_frac] (log scale
## bounded by [member log_floor] / [member log_ceiling]) when drawn. Runtime
## state (not exported / not spec) — sized to [member axes] and written
## through [method set_value].
var _values: PackedFloat32Array = PackedFloat32Array()

## Log-scale floor/ceiling axis values are normalized against before
## plotting (#273). D-18 makes INT a deliberate runaway (thousands) while
## CON/STR/DEX sit in the tens and WIS is bounded 100-200 -- three orders of
## magnitude on one polygon, so a linear plot is unreadable and log scale is
## forced. Bounds are static and SHARED across every entity's radar (not
## per-entity dynamic) because the radar exists for cross-entity comparison
## (#228 renders an enemy's radar against your own) -- a per-entity scale
## would draw two different entities as visually identical shapes.
##
## PLACEHOLDER TUNING VALUES: 1 -> 10_000 spans the designed attribute range
## (D-18) with headroom above CON/STR/DEX (tens) and WIS (100-200), and below
## INT's runaway (thousands+). Revisit once real endgame INT values are known.
@export var log_floor: float = 1.0:
	set(v):
		log_floor = max(0.0001, v)
		queue_redraw()
@export var log_ceiling: float = 10000.0:
	set(v):
		log_ceiling = v
		queue_redraw()

## Maps a plotted value onto [0, 1] on a log scale bounded by
## [member log_floor] / [member log_ceiling]. Values at or below the floor
## (including 0 -- log(0) is -inf, the obvious trap) clamp to the floor and
## render at frac 0.0 rather than erroring or producing -inf/NaN.
func _value_frac(value: float) -> float:
	var lo: float = log(log_floor)
	var hi: float = log(maxf(log_ceiling, log_floor * 1.0001))
	var clamped: float = clampf(value, log_floor, log_ceiling)
	return clampf((log(clamped) - lo) / (hi - lo), 0.0, 1.0)

@export var fill_color: Color = Color(0.82, 0.75, 0.47, 0.14):
	set(v):
		fill_color = v
		queue_redraw()

@export var ring_count: int = 4:
	set(v):
		ring_count = max(1, v)
		queue_redraw()

var _hovered_axis: int = -1

## Half the draw_string width used for axis labels (see label_text_width) —
## reserved outside the label ring so a label's text box can't spill past
## the Control's rect. Kept as a margin against the Control's half-extent,
## not against _get_radius(), so it doesn't compound with ring/plot sizing.
@export var label_margin := 22.0:
	set(v):
		label_margin = v
		queue_redraw()
		
## Total width passed to draw_string for axis labels (HORIZONTAL_ALIGNMENT_CENTER).
@export var label_text_width := 40.0:
	set(v):
		label_text_width = v
		queue_redraw()
## Visual gap between the plotted ring (_get_radius) and the label ring
## (_get_label_radius) so labels don't crowd the outermost ring line.
@export var label_ring_gap := 10.0:
	set(v):
		label_ring_gap = v
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_resize_values()  # ensure _values matches axes even if the setter didn't fire on default init
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)


## Replace the axis set (labels + colors) in one call and reset all plotted
## values to zero. The Attributes Panel drives this instead of poking parallel
## arrays (#241).
func configure(specs: Array[AxisSpec]) -> void:
	axes = specs  # setter resizes _values + redraws
	_values.fill(0.0)
	queue_redraw()


## Set the plotted value for one axis; out-of-range indices are ignored.
func set_value(index: int, value: float) -> void:
	if index < 0 or index >= _values.size():
		return
	_values[index] = value
	queue_redraw()


func _resize_values() -> void:
	_values.resize(axes.size())

func _get_center() -> Vector2:
	return size * 0.5

## Effective plot radius for rings/polygon/dots/axis-lines. Derived from the
## label ring (see _get_label_radius) minus label_ring_gap, so the plot never
## grows into space reserved for labels.
func _get_radius() -> float:
	return max(4.0, _get_label_radius() - label_ring_gap)

## Radius of the ring axis labels are anchored on. Kept label_margin inside
## the Control's half-extent so `label_pos ± label_text_width/2` (the
## draw_string box, see _draw) never crosses Rect2(Vector2.ZERO, size).
func _get_label_radius() -> float:
	return max(0.0, min(size.x, size.y) * 0.5 - label_margin)

func _axis_point(i: int, frac: float) -> Vector2:
	var n := axes.size()
	var angle := -PI / 2.0 + (TAU / float(n)) * i
	return _get_center() + Vector2(cos(angle), sin(angle)) * _get_radius() * frac

## Anchor for axis label i, on the label ring — outside the plotted radius,
## but bounded so it (plus the draw_string offset applied in _draw) stays
## inside the Control's rect. Extracted so a test can assert the bound
## without needing a live _draw() pass.
func _label_anchor(i: int) -> Vector2:
	var n := axes.size()
	var angle := -PI / 2.0 + (TAU / float(n)) * i
	return _get_center() + Vector2(cos(angle), sin(angle)) * _get_label_radius()

func _draw() -> void:
	var n := axes.size()
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
		var frac: float = _value_frac(_values[i]) if i < _values.size() else 0.0
		data_pts.append(_axis_point(i, frac))
	if data_pts.size() >= 3:
		draw_colored_polygon(data_pts, fill_color)
		var outline := data_pts.duplicate()
		outline.append(outline[0])
		draw_polyline(outline, Color(0.82, 0.72, 0.53, 0.9), 1.6, true)

	for i in n:
		var frac: float = _value_frac(_values[i]) if i < _values.size() else 0.0
		var col: Color = axes[i].color if i < axes.size() else Color.WHITE
		var dot_radius := 5.0 if i == _hovered_axis else 3.2
		draw_circle(_axis_point(i, frac), dot_radius, col)

	for i in n:
		var label_pos := _label_anchor(i)
		var col: Color = axes[i].color if i < axes.size() else Color.WHITE
		draw_string(ThemeDB.fallback_font, label_pos - Vector2(label_text_width * 0.5, -4), axes[i].label, HORIZONTAL_ALIGNMENT_CENTER, label_text_width, 12, col)

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
	var n := axes.size()
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
