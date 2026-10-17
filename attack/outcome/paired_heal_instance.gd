class_name PairedHealInstance
extends HealInstance

## The heal twin of [PairedDamageInstance]: a heal RIDER worth a share of its
## [member HitInstance.paired] heal's raw amount — what [PairedDamageEffect]
## mints when the landing it pairs is a heal, so a heal's blast heals. Its
## amount is fixed when the effect runs, in the paired heal's
## [member HitInstance.basis], before the paired heal's crit goes on.
##
## Gated like a damage rider ([method HitInstance.rider_gated]): a dud paired
## heal, or a node its [member HitInstance.land_mask] no longer matches, lands
## nothing — [HealInstance] has no gate of its own. Otherwise it carries the
## paired heal's crit and [method draws_own_crit] keeps it off the stream.


func draws_own_crit() -> bool:
	return false


func land_on(node: NodeCombat, world: CombatWorld) -> void:
	if rider_gated(node, world):
		gated = true
		amount = 0.0
		effective_amount = 0.0
		return
	if paired != null:
		is_crit = paired.is_crit
		crit_multiplier = paired.crit_multiplier
		crit_tier = paired.crit_tier
	super.land_on(node, world)
