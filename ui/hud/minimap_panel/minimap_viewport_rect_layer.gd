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
## [b]The stroke is snapped to the pixel grid[/b] ([method _snap]) — without it
## individual SIDES of the box drop out as the camera moves. A hairline stroke
## is CENTRED on its path, so a path at an integer coordinate covers half of
## each neighbouring pixel column; at this alpha two half-covered columns read
## as nothing at all, and which of the four sides it happens to hit changes
## every time the camera moves a fraction of a world unit.

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


## Land a 1px stroke on whole pixels: round the box to integers, then inset it
## by half a pixel on every side so each edge's CENTRE-LINE sits at `k + 0.5`
## and covers exactly the one pixel row/column it is meant to.
##
## A degenerate box (the camera showing less than ~2px of minimap, i.e. zoomed
## right in) would invert under the inset, so the size floors at zero — a
## cross-hair rather than a box turned inside out.
func _snap(rect: Rect2) -> Rect2:
	var half := outline_width * 0.5
	var origin := rect.position.round() + Vector2(half, half)
	var size := rect.size.round() - Vector2(outline_width, outline_width)
	return Rect2(origin, Vector2(maxf(size.x, 0.0), maxf(size.y, 0.0)))


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
