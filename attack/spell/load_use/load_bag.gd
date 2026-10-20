class_name LoadBag
extends RefCounted

## What one cast's intake rows contribute at each hit, filled by one walk of
## [method Infusion.load_of] dispatching every concept's
## [method LoadUse.spend] ([method Infusion.bag]). Fresh per walk.

## Effects the cast runs after the spell's own [member SpellDef.on_hit_effects]
## at every landing — a [PlantUse]'s [ApplyStatusEffect]s.
var riders: Array[OnHitEffect] = []
## The load the hit spends as a blast ([DetonateEffect]) — a [DetonateUse]'s.
var detonate_load: int = 0
