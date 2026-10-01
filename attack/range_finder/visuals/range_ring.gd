@tool
class_name RangeRing
extends Node2D

## Visual for a single Euclidean reach ring. Live-tweakable in the editor —
## drop a scene that inherits this and override colours / line widths to
## specialize without touching the finder or overlay code.

@export var radius: float = 0.0:
	set(value):
		radius = value
		queue_redraw()

@export var color: Color = Color(1.0, 0.85, 0.0, 0.30):
	set(value):
		color = value
		queue_redraw()

@export var line_width: float = 1.5:
	set(value):
		line_width = value
		queue_redraw()

@export_range(8, 256, 1) var segments: int = 64:
	set(value):
		segments = value
		queue_redraw()


## Fraction of each dash period drawn lit: 1 = solid, 0 = nothing drawn.
## Ranged reach circles carry shots left / max shots here.
@export_range(0.0, 1.0, 0.01) var fill: float = 1.0:
	set(value):
		fill = value
		queue_redraw()

## Equal periods around the circle when [member fill] < 1.
@export_range(1, 64, 1) var dash_periods: int = 12:
	set(value):
		dash_periods = value
		queue_redraw()


## Lit arcs of a reach circle dashed by [param p_fill] over [param periods]
## equal periods: x = start angle, y = end angle (radians). fill >= 1 is one
## full span, fill <= 0 is empty; otherwise each period starts TAU/periods
## after the last and is lit for TAU*fill/periods.
static func dash_spans(p_fill: float, periods: int) -> PackedVector2Array:
	var spans := PackedVector2Array()
	if p_fill >= 1.0:
		spans.append(Vector2(0.0, TAU))
		return spans
	if p_fill <= 0.0 or periods <= 0:
		return spans
	var step := TAU / periods
	var lit := step * p_fill
	for i in periods:
		var start := step * i
		spans.append(Vector2(start, start + lit))
	return spans


## Draws the reach circle on [param canvas], dashed by [param p_fill]: one
## [method CanvasItem.draw_arc] per lit span, each arc's points scaled from
## [param p_segments] (a full circle's count) by its angle, minimum 2. The
## single home of the dash rule — this node's [method _draw] and the
## highlight overlay both call it.
static func draw_reach(canvas: CanvasItem, center: Vector2, p_radius: float, p_fill: float,
		periods: int, p_color: Color, width: float, p_segments: int) -> void:
	if p_radius <= 0.0:
		return
	for span in dash_spans(p_fill, periods):
		var points := maxi(2, ceili(p_segments * (span.y - span.x) / TAU))
		canvas.draw_arc(center, p_radius, span.x, span.y, points, p_color, width)


func configure(p_position: Vector2, p_radius: float) -> void:
	position = p_position
	radius = p_radius


func _draw() -> void:
	draw_reach(self, Vector2.ZERO, radius, fill, dash_periods, color, line_width, segments)
