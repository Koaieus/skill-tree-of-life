@tool
class_name PairedDamageEffect
extends OnHitEffect

## The landing's own hit, again, worth [member fraction] of its stored raw
## amount ([member HitLanding.raw_amount]) on the landed node, carrying the
## landing's pairing, key and beat. Its kind is the landing's: a landing riding
## a heal ([member HitLanding.paired] a [HealInstance]) pairs a
## [PairedHealInstance] in the heal's basis; any other pairs a
## [PairedDamageInstance] of [member HitLanding.raw_type]. When the landing
## rides a hit (an arrow, a blade contact, a heal) it duds with it and takes
## its crit; a damage spell landing has no paired hit, so its shrapnel stands
## alone, while a heal spell's landing rides its heal.
## Mode-agnostic; wrapped in a [SplashEffect] or [BlastEffect] it is a blast,
## each damage copy mitigated by its own node's armour. No raw amount, no hit.

## The share of the landing's raw (pre-crit, pre-mitigation) amount, whatever
## its kind.
@export_range(0.0, 2.0) var fraction: float = 0.5


func apply(landing: HitLanding) -> void:
	if landing == null or landing.target == null or landing.raw_amount <= 0.0:
		return
	var hit: HitInstance
	var heal := landing.paired as HealInstance
	if heal != null:
		hit = PairedHealInstance.new()
		hit.basis = heal.basis
	else:
		var damage := PairedDamageInstance.new()
		damage.type = landing.raw_type
		hit = damage
	hit.amount = fraction * landing.raw_amount
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
	return "Repeats %s%% of the hit — its damage or its heal." % NumFmt.num(fraction * 100.0)
