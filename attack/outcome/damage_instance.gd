class_name DamageInstance
extends HitInstance

## A single instance of damage produced by an [AttackPlan.resolve] pass.
## Pure data: the attacker (via [member source]) declares the *raw* damage;
## defensive mitigation is applied by [method SkillNode.take_damage] at the
## moment of impact via [Mitigation.apply], which may reclassify [member
## HitInstance.kind] to [constant HitInstance.Kind.HEAL] — see the base
## class docstring.

enum Type {
	PHYSICAL,
	MAGIC,
	TRUE, ## Bypasses mitigation.
}

var type: Type = Type.PHYSICAL


func _init() -> void:
	kind = Kind.DAMAGE


func land_on(node: SkillNode) -> void:
	node.take_damage(amount, self)


func _to_string() -> String:
	var type_name: String = Type.keys()[type]
	var suffix: String = " CRIT" if is_crit else ""
	return "<DamageInstance %s %.1f → %s%s>" % [type_name, amount, target, suffix]
