class_name Mitigation

## Defensive mitigation applied at the moment of impact, inside
## [method SkillNode.take_damage]. Attacker says "5 PHYSICAL"; this turns it
## into the effective post-armor number that actually subtracts HP.
##
## Formula: `final = max(min_damage_taken, raw - armor)`, but only when raw > 0
## (zero incoming damage stays zero — the floor only triggers on a real hit).
## TRUE damage bypasses everything.
##
## [b]Both stats are read node-locally[/b] via [method SkillNode.get_local_value],
## which merges the node's `node_board` bins with the owner's board through one
## [method ModifierBins.compute]. So a node-scoped `armor` modifier — a
## `bunker_addon`, or a core-class aura — actually reaches the damage formula.
## Reading the entity board directly (as this used to) silently discarded every
## node-local defensive modifier while the HUD happily displayed them.
##
## Note the floor is a floor, not a cap: negative `armor` pushes damage *above*
## raw, but only becomes visible once `raw - armor > min_damage_taken` (default
## 3). At raw=1 / armor=-1 the defender still takes 3.
##
## [b]And it cuts the other way, on purpose: a NEGATIVE net `min_damage_taken`
## makes a glancing hit HEAL the defender.[/b] [method compute] returns the
## negative number as-is and [method NodeCombat.take_damage] reclassifies the
## landing to [constant HitInstance.Kind.HEAL] (#381). That is the design, not
## an underflow to guard — docs/design/combat_system.md has always specified
## `damage_floor` "can go negative (heals)", `bunker_addon.tscn` authors `-5`,
## and the owner reaffirmed it 2026-09-04: "the whole design of sprinkling
## `-min_damage_taken` modifiers on the board is to allow to go <0 and actually
## heal from having sufficient armor / tanking low hits heals". Anything that
## clamps this at zero is deleting a mechanic; anything that DROPS such a
## landing from a render pass is the #332-shaped bug fixed in
## [ArrowVolleyCoordinator].

static func apply(raw: DamageInstance, defender: SkillNode) -> float:
	if raw.type == DamageInstance.Type.TRUE:
		return raw.amount
	if raw.amount <= 0.0:
		return 0.0
	var armor: float = 0.0
	var floor_min: float = 0.0
	if defender != null:
		armor = float(defender.get_local_value(&"armor"))
		floor_min = float(defender.get_local_value(&"min_damage_taken"))
	return compute(raw.amount, armor, floor_min)


## The formula itself, free of any board/node lookup.
static func compute(amount: float, armor: float, floor_min: float) -> float:
	if amount <= 0.0:
		return 0.0
	return max(floor_min, amount - armor)
