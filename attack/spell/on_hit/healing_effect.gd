@tool
class_name HealingEffect
extends OnHitEffect

## Healing on-hit: contributes a MAGIC [HealingInstance] sized to the in-flight
## state's [member CastSpell.damage] (yes, `DAMAGE`!) already scaled by propagation.
## The VFX coordinator applies it on projectile arrival.
##
## Visual origin for the produced hit is [member CastSpell.predecessor] when
## present (hops); falls back to [member CastSpell.source] for the seed so
## the first projectile flies from the cast-from node, not from nowhere.

# TODO: finish implementation of healing, from this all the way to VFX

func apply(state: CastSpell, outcome: AttackOutcome) -> void:
	if state.current_node == null or state.damage <= 0.0:
		return
	var hit := HealingInstance.new()
	hit.amount = state.damage
	hit.source = state
	hit.target = state.current_node
	hit.origin = state.predecessor if state.predecessor != null else state.source
	outcome.hits.append(hit)
