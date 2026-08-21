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


## The tail end of resolution: the crit multiplier goes on HERE (#507), not at
## resolve, because a subclass override may have just replaced `amount` with a
## live read (`RangedHitInstance.land_on`) or vetoed the landing entirely
## (`BladeDamageInstance.land_on`) — both of which run before this `super`
## call. A normal hit multiplies by 1.0, so there is no `if is_crit` to forget.
func land_on(node: SkillNode) -> void:
	CritRoll.apply(self)
	node.take_damage(amount, self)


func _to_string() -> String:
	var type_name: String = Type.keys()[type]
	var suffix: String = " CRIT" if is_crit else ""
	return "<DamageInstance %s %.1f → %s%s>" % [type_name, amount, target, suffix]
