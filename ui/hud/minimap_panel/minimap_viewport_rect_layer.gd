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
func set_view_rect(rect: Rect2) -> void:
	if _has_rect and rect.is_equal_approx(_rect):
		return
	_has_rect = true
	_rect = rect
	queue_redraw()


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
	draw_rect(_rect, outline_color, false, outline_width)
