class_name CleansePriceInstance
extends DamageInstance

## The HP a cleansed node pays for the stacks cleared off it ([PayWorthTerm]):
## a plain TRUE damage hit that never draws its own crit — a crit on the
## cleanse multiplies the stacks cleared, and the price follows the clears,
## so rolling it again would charge the crit twice. A rebuilt record never
## sees this class: a peer lands a plain [DamageInstance] with the
## authority's number and crit flags, as for [PairedDamageInstance].


func draws_own_crit() -> bool:
	return false
