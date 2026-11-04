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
## paired heal's crit ([method HitInstance.copy_crit_from], the base rider
## contract) and never draws from the stream.


func land_on(node: NodeCombat, world: CombatWorld) -> void:
	if rider_gated(node, world):
		gated = true
		amount = 0.0
		effective_amount = 0.0
		return
	super.land_on(node, world)
