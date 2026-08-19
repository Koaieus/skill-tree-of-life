class_name DamageInstance
extends RefCounted

## A single instance of damage produced by an [AttackPlan.resolve] pass.
## Pure data: the attacker (via [member source]) declares the *raw* damage;
## defensive mitigation is applied by [method SkillNode.take_damage] at the
## moment of impact via [Mitigation.apply].

enum Type {
	PHYSICAL,
	MAGIC,
	TRUE, ## Bypasses mitigation.
}

var amount: float = 0.0
var type: Type = Type.PHYSICAL
## Who/what produced this hit — [AttackPlan], [SpellDef], or any RefCounted.
## Routed back through the [signal Events.skill_node_damaged] payload so UI
## can attribute the number / decide on flash color.
var source: Variant = null
## The node this hit lands on.
var target: SkillNode = null
## The node the hit originated from (firing position / source node).
## Optional; used by VFX (tracer spawn point) and future range-falloff math.
var origin: SkillNode = null

## Whether this hit was elevated to a critical strike. Set by the
## resolver's crit pass (stat roll + condition check). The VFX layer
## reads this for emphasis visuals.
var is_crit: bool = false

## The effective multiplier applied on a crit (default 1.0 = normal hit).
## Set by the resolver from the caster's crit_multiplier stat.
var crit_multiplier: float = 1.0

## Seconds from volley start (t=0, when RangedAttackPlan.resolve returned)
## until this hit's VFX visually reaches its target — launch stagger + flight
## ([code]index * RangedDamageFormula.LAUNCH_STAGGER + distance /
## PROJECTILE_SPEED[/code]), so the recorded timeline is replay-complete: the
## whole volley's launch/impact schedule reconstructs from [code]outcome.hits[/code]
## alone, no VFX-layer secret. The presentation-clock analogue of melee's
## per-event [code]BladeHitEvent.t[/code] (see MeleeAttackPlan.resolve/last_events)
## and magic's fixed propagation clock. 0.0 for hit types that don't yet compute
## one; a VFX coordinator reads this to schedule its delayed reveal signal
## instead of firing synchronously with model mutation (#479/#481).
var arrival_time: float = 0.0

## Post-[Mitigation] HP delta — what [method SkillNode.take_damage] actually
## subtracted. Filled in by take_damage the instant it applies this instance
## (still ahead of any VFX reveal), since [member amount] is the attacker's
## raw pre-mitigation number and a reveal that shows raw would over-report
## whenever armor/[code]min_damage_taken[/code] changed what actually landed.
## 0.0 until take_damage runs.
var effective_amount: float = 0.0


func _to_string() -> String:
	var type_name: String = Type.keys()[type]
	var suffix: String = " CRIT" if is_crit else ""
	return "<DamageInstance %s %.1f → %s%s>" % [type_name, amount, target, suffix]
