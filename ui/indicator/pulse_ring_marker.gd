@tool
class_name PulseRingMarker
extends Indicator

## A band ring whose brightness pulses on the shared wall clock
## ([code]Time.get_ticks_msec()[/code]), easing between two NAMED tiers —
## [member Indicator.tier] at rest, [member peak_tier] at the crest — never a
## hand-picked stop (`.claude/rules/hdr-color.md`). Subclasses shift the phase
## through [method _phase_offset_s]; [member peak_tier] equal to the tier = static.

@export var ring_inner_offset: float = 9.0:
	set(value):
		ring_inner_offset = value
		_apply_geometry()
@export var ring_width: float = 4.0:
	set(value):
		ring_width = value
		_apply_geometry()
## One full pulse, seconds.
@export_range(0.05, 10.0, 0.01) var period_s: float = 1.2
## The crest's named tier.
@export var peak_tier: Emissive.Tier = Emissive.Tier.ALERT:
	set(value):
		peak_tier = value
		_update_modulate()


## The pulse phase 0..1 (0 = rest tier, 1 = peak tier) at wall time
## [param t_s]; peaks when [code]t_s ≡ _phase_offset_s()[/code] (mod the period).
func brightness_at(t_s: float) -> float:
	if peak_tier == tier or period_s <= 0.0:
		return 0.0
	return 0.5 + 0.5 * cos(TAU * (t_s - _phase_offset_s()) / period_s)


## Seconds this ring's crest trails the shared clock's. Default 0.
func _phase_offset_s() -> float:
	return 0.0


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
