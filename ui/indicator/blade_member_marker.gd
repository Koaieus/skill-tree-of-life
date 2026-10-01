@tool
class_name BladeMemberMarker
extends Indicator

## A melee blade member: a band ring whose brightness pulses on a shared
## wall clock ([code]Time.get_ticks_msec()[/code]), delayed by
## [code]order * ripple_step_s[/code] — so the pulse runs out from the pivot
## along the blade with no coordinator. The pulse adds EV stops on top of the
## named [member Indicator.tier]; [member ripple_gain] 0 = static.

@export var ring_inner_offset: float = 9.0:
	set(value):
		ring_inner_offset = value
		_apply_geometry()
@export var ring_width: float = 4.0:
	set(value):
		ring_width = value
		_apply_geometry()
## One full pulse, seconds.
@export_range(0.05, 10.0, 0.01) var ripple_period_s: float = 1.2
## Delay per [member Indicator.order] step, seconds.
@export_range(0.0, 2.0, 0.01) var ripple_step_s: float = 0.12
## Peak brightness add, EV stops over the tier. 0 = no ripple.
@export_range(0.0, 4.0, 0.05) var ripple_gain: float = 0.6:
	set(value):
		ripple_gain = value
		_update_modulate()


## The ripple's brightness add (EV stops) at wall time [param t_s]: peaks
## when [code]t_s ≡ order * ripple_step_s[/code] (mod the period).
func brightness_at(t_s: float) -> float:
	if ripple_gain <= 0.0 or ripple_period_s <= 0.0:
		return 0.0
	var phase := (t_s - float(maxi(order, 0)) * ripple_step_s) / ripple_period_s
	return ripple_gain * (0.5 + 0.5 * cos(TAU * phase))


func _process(delta: float) -> void:
	super(delta)
	if ripple_gain > 0.0:
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
