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
