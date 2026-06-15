@tool
class_name DamageEffect
extends OnHitEffect

## Standard on-hit: contributes a MAGIC [DamageInstance] sized to the in-flight
## state's [member SpellState.damage] (already scaled by propagation). The
## VFX coordinator applies it on projectile arrival.
##
## Visual origin for the produced hit is [member SpellState.predecessor] when
## present (hops); falls back to [member SpellState.source] for the seed so
## the first projectile flies from the cast-from node, not from nowhere.


func apply(state: SpellState, outcome: AttackOutcome) -> void:
	if state.current_node == null or state.damage <= 0.0:
		return
	var hit := DamageInstance.new()
	hit.amount = state.damage
	hit.type = DamageInstance.Type.MAGIC
	hit.source = state
	hit.target = state.current_node
	hit.origin = state.predecessor if state.predecessor != null else state.source
	outcome.hits.append(hit)
