@tool
class_name FlatAddProgression
extends HopDamageProgression

## Arithmetic progression with an ABSOLUTE common difference: damage gains
## [member increment] each hop, regardless of who is casting.
##
## [b]The compression is the point — do not "fix" it.[/b] Because the increment
## is absolute while the seed scales with the caster, the spell's edge over its
## own seed collapses as INT rises:
## [codeblock]
## caster    seed   +2/hop at hop 6   ratio to seed
## INT 10      2          14              7.00×
## INT 1000  101         113              1.12×
## [/codeblock]
## Absolute damage still climbs with INT; what compresses is the spell's
## advantage — so a flat-ramp spell is strong for a novice and marginal for an
## archmage, which is exactly the niche D-33 wants. This was once reported as a
## "dimensional bug" and deleted; see the D-32 amendment
## ([code]docs/design/mvp_decisions.md[/code], 2026-08-03), which is left
## standing as the trap marker. Want the relative behaviour? That is a
## different progression — [ScaledAddProgression] — chosen deliberately.
##
## Pairs with [SumDamageReducer] + [ConvergenceCritCondition] on the Resonator
## (#352), where the convergence crit is the only multiplicative in the spell.

@export var increment: float = 0.0


func apply(damage: float, _seed: float, _hop_index: int) -> float:
	return damage + increment


func get_description() -> String:
	if is_equal_approx(increment, 0.0):
		return ""
	if is_equal_approx(increment, roundf(increment)):
		return "+%d per hop" % int(increment)
	return "+%.1f per hop" % increment
