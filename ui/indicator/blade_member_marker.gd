@tool
class_name BladeMemberMarker
extends PulseRingMarker

## A melee blade member: its pulse trails the shared clock by
## [code]order * ripple_step_s[/code], so the crest runs out from the pivot
## along the blade with no coordinator.

## Delay per [member Indicator.order] step, seconds.
@export_range(0.0, 2.0, 0.01) var ripple_step_s: float = 0.12


func _phase_offset_s() -> float:
	return float(maxi(order, 0)) * ripple_step_s
