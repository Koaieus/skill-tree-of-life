class_name PairedDamageInstance
extends DamageInstance

## A damage RIDER worth a share of its [member HitInstance.paired] hit's raw
## amount — [PairedDamageEffect]'s hit, the Explosive arrow's blast. Its
## [member HitInstance.amount] is fixed when the effect runs (plan compile),
## before the paired arrow's own crit multiplies the arrow's amount at land,
## so the share is of the RAW number and each landed node mitigates it once.
##
## It carries the paired hit's crit rather than rolling its own: the arrow
## lands first on the shared beat, and [method land_on] copies its
## `is_crit` / `crit_multiplier` / `crit_tier` before the multiplier goes on.
## A rebuilt record never sees this class — a peer lands a plain
## [DamageInstance] with the authority's number and crit flags.


func land_on(node: NodeCombat, world: CombatWorld) -> void:
	if paired != null and not rider_gated(node):
		is_crit = paired.is_crit
		crit_multiplier = paired.crit_multiplier
		crit_tier = paired.crit_tier
	super.land_on(node, world)
