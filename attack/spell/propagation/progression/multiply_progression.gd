@tool
class_name MultiplyProgression
extends HopDamageProgression

## Geometric progression: damage is multiplied by [member factor] each hop —
## [member factor] is literally the progression's common ratio. 0.5 = falloff
## (Lightning), 1.5 = rampup (Reverberator / Leafblower), 1.0 = flat.
##
## Relative to the seed, so it SCALES WITH THE CASTER: hop n is
## [code]seed × factor^n[/code], and doubling the caster's
## [code]spell_damage[/code] doubles every hit (D-32).

@export var factor: float = 1.0


func apply(damage: float, _seed: float, _hop_index: int) -> float:
	return damage * factor


func get_description() -> String:
	if is_equal_approx(factor, 1.0):
		return ""
	if is_equal_approx(factor, roundf(factor)):
		return "×%d per hop" % int(factor)
	return "×%.1f per hop" % factor
