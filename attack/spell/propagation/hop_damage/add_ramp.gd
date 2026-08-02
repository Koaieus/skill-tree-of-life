@tool
class_name AddRamp
extends HopDamage

## Adds [member increment] to damage each hop. The drop-in replacement for
## the bespoke [code]TrailBlazerStep.per_hop_increment[/code] field — flat
## arithmetic ramp. The Resonator spell (#352) pairs this with
## [SumDamageReducer] + [ConvergenceCritCondition] so that the convergence
## crit is the only multiplicative in the spell.

@export var increment: float = 0.0


func apply(damage: float, _hop_index: int) -> float:
	return damage + increment


func get_description() -> String:
	if is_equal_approx(increment, 0.0):
		return ""
	if is_equal_approx(increment, roundf(increment)):
		return "+%d per hop" % int(increment)
	return "+%.1f per hop" % increment