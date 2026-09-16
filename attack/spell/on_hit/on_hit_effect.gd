@tool
@abstract
class_name OnHitEffect
extends Resource

## What happens at every node the spell lands on. Multiple effects per spell
## run in order — usually just [DamageEffect], but extras like "Mark for
## Detonate" or "Stun for one turn" stack alongside as their own subclasses.
##
## Effects don't apply damage directly — they push [DamageInstance]s onto
## [param outcome] so the VFX layer can apply them on projectile arrival,
## keeping damage-timing in sync with visuals (the existing ranged-volley
## pattern). Status effects that don't fit that model can mutate world
## state at apply time; the resolver runs in editor too, so guard with
## [code]Engine.is_editor_hint()[/code] where appropriate.


## [param lctx]'s [code]payload[/code] is what used to be [code]state[/code];
## [code]lctx.cast.outcome[/code] is what used to be the [code]outcome[/code]
## param (#356).
@abstract func apply(lctx: LandingContext) -> void

## Player-facing line for this effect in [SpellTooltip]'s On-arrival section
## (#764). [param spell] supplies [member SpellDef.power] for an effect that
## quotes a number, through [method SpellResolver.impact_damage] (D-32 — the
## one home for that expression; never re-derive [code]spell_damage × power[/code]
## here). [param board] is the same no-cast-from-node preview path every other
## tooltip describer uses ([method RangeFinder.get_description]) — pass the
## caster's board to get the number their own stats moved, and the caller
## marks the line gold when that differs from the unscaled ([code]board =
## null[/code]) reading. Null [param spell] (no preview context) still returns
## a description, just without a number.
func get_description(_spell: SpellDef = null, _board: StatBoard = null) -> String:
	return ""


## Shared number formatting for subclass [method get_description]s — whole
## number when the value already is one, one decimal otherwise. Twin of
## [method RangeFinder._fmt_num] — same four lines, different Resource tree;
## kept local so an effect's own describer reads correctly in isolation and
## neither hierarchy has to depend on the other. Fold them if a third appears.
## [method _fmt_num] for a [member HitInstance.basis]-denominated number: a
## FLAT amount reads as-is, a PERCENT_MAX coefficient as a percentage of the
## target's max hp — the two describers that quote a spell's impact number
## ([DamageEffect], [HealEffect]) share it.
static func _fmt_amount(v: float, basis: HitInstance.AmountBasis) -> String:
	if basis == HitInstance.AmountBasis.PERCENT_MAX:
		return "%s%% of max HP" % _fmt_num(v * 100.0)
	return _fmt_num(v)


static func _fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "%.1f" % v
