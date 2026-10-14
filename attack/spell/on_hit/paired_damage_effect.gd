@tool
class_name PairedDamageEffect
extends OnHitEffect

## Damage worth [member fraction] of the landing's stored raw amount
## ([member HitLanding.raw_amount], its type too), on the landed node — a
## [PairedDamageInstance] carrying the landing's pairing, key and beat. When the
## landing rides a hit (an arrow, a blade contact) it duds with it and takes its
## crit; a spell landing has no paired hit, so its shrapnel stands alone.
## Mode-agnostic; wrapped in a [SplashEffect] or [BlastEffect] it is a blast,
## each copy mitigated by its own node's armour. No raw amount, no hit.

## The share of the landing's raw (pre-crit, pre-mitigation) amount.
@export_range(0.0, 2.0) var fraction: float = 0.5


func apply(landing: HitLanding) -> void:
	if landing == null or landing.target == null or landing.raw_amount <= 0.0:
		return
	var hit := PairedDamageInstance.new()
	hit.amount = fraction * landing.raw_amount
	hit.type = landing.raw_type
	hit.attacker = landing.attacker
	hit.source = landing.source
	hit.origin = landing.origin
	hit.read_node = landing.read_node
	hit.target = landing.target
	hit.structural_key = landing.structural_key
	hit.paired = landing.paired
	hit.hit_key = landing.hit_key
	landing.hits.append(hit)


func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	return "Deals %s%% of the hit's damage." % NumFmt.num(fraction * 100.0)
