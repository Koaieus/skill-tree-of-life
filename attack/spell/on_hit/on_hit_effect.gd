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


@abstract func apply(state: CastSpell, outcome: AttackOutcome) -> void

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
## number when the value already is one, one decimal otherwise. Mirrors
## [method RangeFinder._fmt_num]; kept local so an effect's own describer
## reads correctly in isolation.
static func _fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "%.1f" % v
