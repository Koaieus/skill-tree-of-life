@tool
class_name PairedDamageEffect
extends OnHitEffect

## Damage worth [member fraction] of the landing's [member HitLanding.paired]
## hit's raw amount, on the landed node — a [PairedDamageInstance] carrying the
## landing's pairing, key and beat, so it duds with its arrow and takes its
## crit. Mode-agnostic (an [AmmoType] may carry it); wrapped in a
## [SplashEffect] it is a blast, each copy mitigated by its own node's armour.
## A landing with no paired hit (a spell's) emits nothing — a spell uses
## [DamageEffect].

## The share of the paired hit's raw (pre-crit, pre-mitigation) amount.
@export_range(0.0, 2.0) var fraction: float = 0.5


func apply(landing: HitLanding) -> void:
	var paired := landing.paired as DamageInstance if landing != null else null
	if paired == null or landing.target == null:
		return
	var hit := PairedDamageInstance.new()
	hit.amount = fraction * paired.amount
	hit.type = paired.type
	hit.attacker = landing.attacker
	hit.source = landing.source
	hit.origin = landing.origin
	hit.read_node = landing.read_node
	hit.target = landing.target
	hit.structural_key = landing.structural_key
	hit.paired = paired
	hit.hit_key = landing.hit_key
	landing.hits.append(hit)


func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	return "Deals %s%% of the arrow's damage." % NumFmt.num(fraction * 100.0)
