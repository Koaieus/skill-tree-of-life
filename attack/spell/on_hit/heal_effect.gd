@tool
class_name HealEffect
extends OnHitEffect

## Healing on-hit: contributes a [HealInstance] sized to the in-flight
## state's [member CastSpell.damage] (yes, `DAMAGE`!) already scaled by propagation.
## The VFX coordinator applies it on projectile arrival. Renamed from
## `HealingEffect` (#381) to parallel `DamageEffect`.
##
## Visual origin for the produced hit is [member CastSpell.predecessor] when
## present (hops); falls back to [member CastSpell.source] for the seed so
## the first projectile flies from the cast-from node, not from nowhere.

func apply(state: CastSpell, outcome: AttackOutcome) -> void:
	if state.current_node == null or state.damage <= 0.0:
		return
	var heal := HealInstance.new()
	heal.amount = state.damage
	heal.source = state
	heal.target = state.current_node
	heal.origin = state.predecessor if state.predecessor != null else state.source
	outcome.hits.append(heal)
