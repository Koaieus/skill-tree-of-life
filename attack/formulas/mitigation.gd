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
