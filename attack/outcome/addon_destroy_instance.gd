class_name AddonDestroyInstance
extends HitInstance

## A bunker member hitting a bunker plate past the defender's
## [member BunkerAddon.destroy_momentum]: [member target]'s Bunker addon is
## knocked off. No HP — [member amount] stays 0. Decided on the shadow
## resolve; only the replay ([method land_on] on a live world) frees the
## addon, so the authority and every peer remove it through the record alone.


func _init() -> void:
	kind = Kind.ADDON_DESTROY


func land_on(_node: NodeCombat, _world: CombatWorld) -> void:
	effective_amount = 0.0
