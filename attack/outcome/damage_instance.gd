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


func _to_string() -> String:
	var type_name: String = Type.keys()[type]
	return "<DamageInstance %s %.1f → %s>" % [type_name, amount, target]
