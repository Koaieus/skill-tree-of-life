@tool
class_name MinimapViewportRectLayer
extends Control

## The white outline showing what the main view currently covers (#453).
##
## Split out of [MinimapGraphLayer] because its cadence is the opposite: this
## moves on every pan and breathes through every zoom tween, while the graph
## underneath is static for whole turns at a time. One `draw_rect`.
##
## Holds a rect in MINIMAP-LOCAL space, not a camera — [MinimapPanel] owns the
## world mapping and the polling, so this layer has nothing to keep in sync.
##
## [b]The box is four FILLED spans, not a stroked rect[/b] — otherwise
## individual sides drop out as the camera moves. Two compounding reasons, and
## only the second one actually settles it:
##
##  1. A hairline stroke is CENTRED on its path, so a path on a pixel boundary
##     covers half of each neighbouring column and at this alpha reads as
##     nothing. [method _snap] handles that much.
##  2. But snapping to whole LOCAL pixels buys nothing on its own, because
##     `project.godot` sets `stretch/mode = "canvas_items"` against a 1440x960
##     base: on any other window size the entire HUD is scaled by a non-integer
##     factor, so one local pixel is not one device pixel and a snapped path
##     still lands wherever it lands. That is why the flicker survived the
##     first fix.
##
## A filled span always covers area — it can dim under an awkward scale, but it
## cannot vanish the way a zero-area path can. [method _device_pixel_width]
## then keeps each span at least one DEVICE pixel thick by reading the actual
## canvas scale, so the box stays visible at any window size.

@export var outline_color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var outline_width: float = 1.0

## Bumped on every `_draw`, the same way [MinimapGraphLayer] does it — so
## "an unchanged camera does not redraw" is an assertion rather than a claim.
var draw_count: int = 0

var _rect: Rect2 = Rect2()
var _has_rect: bool = false


## No-ops on an unchanged rect: the panel polls the camera every frame, and
## most frames it has not moved. Redrawing anyway would be cheap but would also
## make the whole "redraw only on change" split untestable.
##
## Snapping happens HERE rather than in [method _draw] so the comparison is
## made on the snapped value too — sub-pixel camera drift then lands on the
## same box and costs no redraw at all, which the raw rect never would.
func set_view_rect(rect: Rect2) -> void:
	var snapped_rect := _snap(rect)
	if _has_rect and snapped_rect.is_equal_approx(_rect):
		return
	_has_rect = true
	_rect = snapped_rect
	queue_redraw()


## Round the box to whole local pixels. Crisp when the canvas scale happens to
## be 1, harmless when it is not — and load-bearing either way as the input to
## the equality check in [method set_view_rect], which is what makes sub-pixel
## camera drift free.
##
## Note it no longer INSETS by half a stroke: the sides are filled spans drawn
## inward from these bounds ([method _edge_rects]), not a centre-line.
func _snap(rect: Rect2) -> Rect2:
	return Rect2(rect.position.round(), rect.size.round().maxf(0.0))


## The stroke width in LOCAL units that renders at least one device pixel
## thick, given whatever non-integer factor `canvas_items` stretch is currently
## applying to the HUD. Falls back to the authored width when the transform is
## degenerate (a layer not yet in a viewport, e.g. a unit test).
func _device_pixel_width() -> float:
	var canvas_scale := get_global_transform_with_canvas().get_scale()
	var factor := minf(absf(canvas_scale.x), absf(canvas_scale.y))
	if factor <= 0.0 or not is_finite(factor):
		return outline_width
	return maxf(outline_width, 1.0 / factor)


## The box as four filled spans — top and bottom run the full width, the sides
## fill only what is left between them so the corners are not drawn twice (at
## this alpha a double-drawn corner is visibly brighter).
##
## Pure and static so the geometry is unit-testable without a viewport, a
## camera or a canvas scale.
static func _edge_rects(rect: Rect2, width: float) -> Array[Rect2]:
	var w := minf(width, minf(rect.size.x, rect.size.y) * 0.5)
	if w <= 0.0:
		return []
	var inner_height := maxf(rect.size.y - w * 2.0, 0.0)
	return [
		Rect2(rect.position.x, rect.position.y, rect.size.x, w),
		Rect2(rect.position.x, rect.end.y - w, rect.size.x, w),
		Rect2(rect.position.x, rect.position.y + w, w, inner_height),
		Rect2(rect.end.x - w, rect.position.y + w, w, inner_height),
	]


## Take the outline down — no camera bound, or a level with none at all.
func clear_view_rect() -> void:
	if not _has_rect:
		return
	_has_rect = false
	queue_redraw()


func _draw() -> void:
	draw_count += 1
	if not _has_rect:
		return
	for edge in _edge_rects(_rect, _device_pixel_width()):
		draw_rect(edge, outline_color)
