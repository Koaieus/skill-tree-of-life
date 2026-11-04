class_name PairedDamageInstance
extends DamageInstance

## A damage RIDER worth a share of its [member HitInstance.paired] hit's raw
## amount — [PairedDamageEffect]'s hit, a future Explosive arrow's blast. Its
## [member HitInstance.amount] is fixed when the effect runs (plan compile),
## before the paired arrow's own crit multiplies the arrow's amount at land,
## so the share is of the RAW number and each landed node mitigates it once.
##
## It carries the paired hit's crit rather than rolling its own — the base
## rider contract: [method CritRoll.decide] draws the arrow's crit and
## [method HitInstance.copy_crit_from] hands it down before the multiplier
## goes on, and the rider never touches the outcome's crit stream. A rebuilt
## record never sees this class — a peer lands a plain [DamageInstance] with
## the authority's number and crit flags.
