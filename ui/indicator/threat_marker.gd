@tool
class_name ThreatMarker
extends Indicator

## A predicted threat to the blade: a band ring with a slow brightness pulse —
## a warning, not an alarm, so the default tier is LABEL and the pulse only
## breathes up to [member peak_tier].

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
## The crest's named tier; the pulse eases [member Indicator.tier] -> this
## and back. Equal to [member Indicator.tier] = static.
@export var peak_tier: Emissive.Tier = Emissive.Tier.VALUE:
	set(value):
		peak_tier = value
		_update_modulate()


## The pulse phase 0..1 (0 = rest tier, 1 = peak tier) at wall time [param t_s].
func brightness_at(t_s: float) -> float:
	if peak_tier == tier or pulse_period_s <= 0.0:
		return 0.0
	return 0.5 + 0.5 * cos(TAU * t_s / pulse_period_s)


func _process(delta: float) -> void:
	super(delta)
	if peak_tier != tier:
		_update_modulate()


func _update_modulate() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	modulate = Emissive.at(tint, lerpf(Emissive.stops(tier), Emissive.stops(peak_tier), brightness_at(now)))


func _apply_geometry() -> void:
	var ring := get_node_or_null(^"%Ring") as IndicatorRingBand
	if ring != null:
		var w := stroke(ring_width)
		ring.width = w
		ring.centerline = SkillNode.ring_centerline(radius, ring_inner_offset, w)
