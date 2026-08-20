class_name EntityCombat
extends RefCounted

## The live combat-state slice for an [Entity] (#498 step 1 — see
## docs/domain/attack-timeline.md). Step 1 moves exactly one thing here: the
## revoke sweep + navigator-mirror removal that [AllocationSystem.force_deallocate]
## runs on the node's *previous owner*. Everything else about a forced
## deallocation (the ownership write, presentation, and the `_on_node_deallocated`
## dispatch) stays where it was — see [method AllocationSystem.force_deallocate].
##
## [member host] is assigned once, at construction, and is never reassigned —
## no public setter. See [NodeCombat] for why (step 2's `snapshot()` is what
## makes a null host possible; step 1 never constructs one).
##
## Effect-hook placement rule (docs/domain/attack-timeline.md's "one boundary
## that can rot"): an [Effect] hook that changes a number belongs on
## [EntityCombat]; a hook that only tells someone belongs on the host. Today
## the only hook reached from this file's step-1 scope is the revoke sweep's
## own bookkeeping, not a dispatched hook — `_on_node_deallocated` itself still
## dispatches from [AllocationSystem], unmoved, because moving it is step 2/3
## work (it needs a slice-aware [EffectContext], not built yet).
var host: Entity


func _init(p_host: Entity) -> void:
	host = p_host


## Strip [param node]'s footprint from [member host]: swapped effect-sets,
## granted effects, entity-scoped modifiers, and the navigator mirror. Called
## by [method AllocationSystem.force_deallocate] on the node's previous owner,
## before ownership clears.
func revoke_node(node: SkillNode) -> void:
	var board := host.stat_board
	# Strip swapped effect-sets BEFORE the revoke sweep — the set leaves were
	# applied outside the effect ledger and would strand otherwise (#376).
	node.clear_scaled_effect_sets(board)
	host.revoke_effects_from(node)
	node.remove_entity_modifiers_from(board)
	if host.navigator != null:
		host.navigator.mirror_remove(node)
