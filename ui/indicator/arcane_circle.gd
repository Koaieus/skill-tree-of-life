@tool
class_name ArcaneCircle
extends PulseRingMarker

## The confirmed magic source: two dashed rings turning in opposite directions
## while the whole circle pulses between [member Indicator.tier] and
## [member PulseRingMarker.peak_tier]. Dashes are [IndicatorDashedBand]s, so
## the dash rule is [method RangeRing.dash_spans]. %Inner sits at the reticle
## convention (inner edge at [member PulseRingMarker.ring_inner_offset]);
## %Outer starts [member ring_gap] past %Inner's outer edge. Each ring's
## rotation is its own spin — nothing outside redraws per frame.

@export_range(1, 64, 1) var outer_dash_count: int = 12:
	set(value):
		outer_dash_count = value
		_apply_geometry()
@export_range(1, 64, 1) var inner_dash_count: int = 8:
	set(value):
		inner_dash_count = value
		_apply_geometry()
## 0 = static; opposite signs make the rings counter-turn.
@export var outer_spin_deg_s: float = 20.0
@export var inner_spin_deg_s: float = -30.0
## Gap from %Inner's outer edge to %Outer's inner edge (world px).
@export var ring_gap: float = 5.0:
	set(value):
		ring_gap = value
		_apply_geometry()


func _process(delta: float) -> void:
	super(delta)
	_spin(^"%Outer", outer_spin_deg_s, delta)
	_spin(^"%Inner", inner_spin_deg_s, delta)


func _spin(path: NodePath, deg_s: float, delta: float) -> void:
	if deg_s == 0.0:
		return
	var ring := get_node_or_null(path) as Node2D
	if ring != null:
		ring.rotation = wrapf(ring.rotation + deg_to_rad(deg_s) * delta, -PI, PI)


func _apply_geometry() -> void:
	var w := stroke(ring_width)
	var inner_centre := SkillNode.ring_centerline(radius, ring_inner_offset, w)
	var inner := get_node_or_null(^"%Inner") as IndicatorDashedBand
	if inner != null:
		inner.width = w
		inner.centerline = inner_centre
		inner.dash_count = inner_dash_count
	var outer := get_node_or_null(^"%Outer") as IndicatorDashedBand
	if outer != null:
		outer.width = w
		outer.centerline = inner_centre + w + ring_gap
		outer.dash_count = outer_dash_count
