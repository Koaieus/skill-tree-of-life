class_name HealingInstance
extends RefCounted

## A single instance of healing produced by an [AttackPlan.resolve] pass.
## Pure data: the healer (via [member source]) declares the *raw* damage;
## defensive mitigation is applied by [method SkillNode.take_damage] at the
## moment of impact via [Mitigation.apply].

# TODO: Make a shared parent with DamageInstance? so objects down the line 
#		can be typed to hold either, and any future subclass would fold in easily

var amount: float = 0.0
## Who/what produced this hit — [AttackPlan], [SpellDef], or any RefCounted.
## Routed back through the [signal Events.skill_node_damaged] payload so UI
## can attribute the number / decide on flash color.
var source: Variant = null
## The node this hit lands on.
var target: SkillNode = null
## The node the hit originated from (firing position / source node).
## Optional; used by VFX (tracer spawn point) and future range-falloff math.
var origin: SkillNode = null

## Whether this hit was elevated to a critical heal. Set by the
## resolver's crit pass (stat roll + condition check). The VFX layer
## reads this for emphasis visuals.
var is_crit: bool = false

## The effective multiplier applied on a crit (default 1.0 = normal hit).
## Set by the resolver from the caster's crit_multiplier stat.
var crit_multiplier: float = 1.0


func _to_string() -> String:
	var suffix: String = " CRIT" if is_crit else ""
	return "<HealingInstance %.1f → %s%s>" % [amount, target, suffix]
