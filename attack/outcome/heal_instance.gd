class_name HealInstance
extends HitInstance

## A single instance of healing produced by an [AttackPlan.resolve] pass —
## renamed from [code]HealingInstance[/code] (#381) to parallel
## [DamageInstance]/[HealEffect]'s naming. Heals aren't run through
## [Mitigation], so [member HitInstance.kind] never reclassifies away from
## [constant HitInstance.Kind.HEAL].


func _init() -> void:
	kind = Kind.HEAL


## Crit multiplier applied at land, same as [method DamageInstance.land_on] —
## see [CritRoll]. Heals crit too (#381).
func land_on(node: NodeCombat, _world: CombatWorld) -> void:
	CritRoll.apply(self)
	node.heal_damage(amount, self)


func _to_string() -> String:
	var suffix: String = " CRIT" if is_crit else ""
	return "<HealInstance %.1f → %s%s>" % [amount, target, suffix]
