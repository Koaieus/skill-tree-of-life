class_name AddonDestroyInstance
extends HitInstance

## A bunker member hitting a bunker plate past the defender's
## [member BunkerAddon.destroy_momentum]: [member target]'s Bunker addon is
## knocked off. No HP — [member amount] stays 0. Decided on the shadow
## resolve; only the replay ([method land_on] on a live world) frees the
## addon, so the authority and every peer remove it through the record alone.


func _init() -> void:
	kind = Kind.ADDON_DESTROY


## Never reached through the applier's slice path (it dispatches here first).
func land_on(_node: NodeCombat, world: CombatWorld) -> void:
	land_destroy(world)


## Shadow: nothing — the decision is already on the record. Live: free the
## target's Bunker; a target or addon already gone is a no-op.
func land_destroy(world: CombatWorld) -> void:
	effective_amount = 0.0
	if world.is_shadow():
		return
	var plate := BunkerAddon.on(target)
	if plate == null:
		return
	target.remove_child(plate)
	plate.queue_free()
