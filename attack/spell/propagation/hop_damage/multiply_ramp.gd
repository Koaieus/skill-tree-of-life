@tool
class_name MultiplyRamp
extends HopDamage

## Multiplies damage by [member factor] each hop. The drop-in replacement
## for the old [code]damage_multiplier_per_hop[/code] scalar — 0.5 = falloff
## (Lightning), 1.5 = rampup (Reverberator / Leafblower), 1.0 = flat.

@export var factor: float = 1.0


func apply(damage: float, _hop_index: int) -> float:
	return damage * factor


func get_description() -> String:
	if is_equal_approx(factor, 1.0):
		return ""
	if is_equal_approx(factor, roundf(factor)):
		return "×%d per hop" % int(factor)
	return "×%.1f per hop" % factor