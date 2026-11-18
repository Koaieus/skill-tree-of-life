class_name LoadBag
extends RefCounted

## What one cast's intake rows contribute at each hit, filled by one walk of
## [method Infusion.load_of] dispatching every concept's
## [method LoadUse.spend] ([method Infusion.bag]). Fresh per walk.

## Effects the cast runs after the spell's own [member SpellDef.on_hit_effects]
## at every landing — a [PlantUse]'s [ApplyStatusEffect]s.
var riders: Array[OnHitEffect] = []

## The Ice shape's hop cut, 1 per load ([ConcentrateUse]); 0 = no concentrate.
## Asked, not applied: the def's `max_hops` is never written.
var hop_cut: int = 0
## The concentrate's payload bonus per hop removed
## ([member ConcentrateUse.bonus_per_hop]); 0 with no concentrate.
var bonus_per_hop: float = 0.0


## Hops this cast removes from a walk of [param max_hops]
## ([member PropagationConfig.max_hops]): `min(hop_cut, max_hops)`; 0 on a walk
## with nothing to cut (0 hops, or unbounded).
func hops_removed(max_hops: float) -> int:
	if hop_cut <= 0 or max_hops <= 0.0 or is_inf(max_hops):
		return 0
	return mini(hop_cut, int(max_hops))


## The payload multiplier on a walk of [param max_hops]:
## `1 + bonus_per_hop × hops_removed`. Exactly 1 with no cut.
func multiplier(max_hops: float) -> float:
	return 1.0 + bonus_per_hop * hops_removed(max_hops)
