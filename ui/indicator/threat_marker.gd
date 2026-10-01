@tool
class_name ThreatMarker
extends Indicator

## A predicted threat to the blade: a band ring with a slow brightness pulse —
## a warning, not an alarm, so the default tier is LABEL and the pulse only
## breathes within it ([member pulse_gain] EV stops at peak).

@export var ring_inner_offset: float = 9.0:
	set(value):
		ring_inner_offset = value
		_apply_geometry()
@export var ring_width: float = 3.0:
	set(value):
		ring_width = value
		_apply_geometry()
## One full pulse, seconds.
@export_range(0.05, 10.0, 0.01) var pulse_period_s: float = 1.6
## Peak brightness add, EV stops over the tier. 0 = static.
@export_range(0.0, 4.0, 0.05) var pulse_gain: float = 0.5:
	set(value):
		pulse_gain = value
		_update_modulate()


## The pulse's brightness add (EV stops) at wall time [param t_s].
func brightness_at(t_s: float) -> float:
	if pulse_gain <= 0.0 or pulse_period_s <= 0.0:
		return 0.0
	return pulse_gain * (0.5 + 0.5 * cos(TAU * t_s / pulse_period_s))


func _process(delta: float) -> void:
	super(delta)
	if pulse_gain > 0.0:
		_update_modulate()


func _update_modulate() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	modulate = Emissive.at(tint, Emissive.stops(tier) + brightness_at(now))


func _apply_geometry() -> void:
	var ring := get_node_or_null(^"%Ring") as IndicatorRingBand
	if ring != null:
		var w := stroke(ring_width)
		ring.width = w
		ring.centerline = SkillNode.ring_centerline(radius, ring_inner_offset, w)
