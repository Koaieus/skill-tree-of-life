@tool
class_name ScaledAddProgression
extends HopDamageProgression

## Arithmetic progression whose common difference is a FRACTION OF THE SEED:
## hop n is [code]seed × (1 + n × seed_fraction_per_hop)[/code]. Linear growth,
## so it stays usable where a geometric ramp explodes (Trailblazer's
## [code]max_hops = 20[/code]) — and unlike [FlatAddProgression] it is relative,
## so it SCALES WITH THE CASTER: doubling [code]spell_damage[/code] doubles
## every hit (D-32).
##
## Linear is a genuinely different shape from geometric, which is why this sits
## beside [MultiplyProgression] rather than being expressed through it.

## Fraction of the seed added per hop. [code]2.0[/code] reads "+200% of the
## seed per hop" — hence the name; a field called `fraction` holding 2.0 would
## read as a bug.
@export var seed_fraction_per_hop: float = 0.0


func apply(damage: float, seed: float, _hop_index: int) -> float:
	return damage + seed * seed_fraction_per_hop


func get_description() -> String:
	if is_equal_approx(seed_fraction_per_hop, 0.0):
		return ""
	return "+%d%% of seed per hop" % int(round(seed_fraction_per_hop * 100.0))
