@tool
class_name DashedRing
extends PlainRing

## A static [PlainRing] broken into [member dash_count] dashes, each lit for
## [member fill] of its period.

@export_range(1, 64, 1) var dash_count: int = 10:
	set(value):
		dash_count = value
		_apply_geometry()
@export_range(0.0, 1.0, 0.01) var fill: float = 0.55:
	set(value):
		fill = value
		_apply_geometry()


func _apply_geometry() -> void:
	super()
	var ring := get_node_or_null(^"%Ring") as IndicatorDashedBand
	if ring != null:
		ring.dash_count = dash_count
		ring.fill = fill
