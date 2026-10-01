@tool
class_name IndicatorDashedBand
extends IndicatorRingBand

## An [IndicatorRingBand] lit only over [member dash_count] equal dashes, each
## [member fill] of its period ([method RangeRing.dash_spans]).

@export_range(1, 64, 1) var dash_count: int = 10:
	set(value):
		dash_count = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var fill: float = 0.55:
	set(value):
		fill = value
		queue_redraw()


func _draw() -> void:
	if centerline <= 0.0 or width <= 0.0:
		return
	var per_dash := maxi(2, segments / maxi(dash_count, 1))
	for span in RangeRing.dash_spans(fill, dash_count):
		draw_arc(Vector2.ZERO, centerline, span.x, span.y, per_dash, Color.WHITE, width, true)
