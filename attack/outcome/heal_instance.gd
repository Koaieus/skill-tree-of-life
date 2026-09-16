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
## see [CritRoll]. Heals crit too (#381). Every heal cures (#875, hub #868
## D7) — [method NodeCombat.cure_debuffs] runs off [member effective_amount],
## the post-clamp number [method NodeCombat.heal_damage] just stamped onto
## `self`, so a heal wasted on a full-health node cures nothing. This is
## deliberately NOT gated behind a spell-specific on-hit effect: any heal,
## from any source, cures.
func land_on(node: NodeCombat, _world: CombatWorld) -> void:
	resolve_amount(node)
	CritRoll.apply(self)
	node.heal_damage(amount, self)
	node.cure_debuffs(effective_amount)


func _to_string() -> String:
	var suffix: String = " CRIT" if is_crit else ""
	return "<HealInstance %.1f → %s%s>" % [amount, target, suffix]
