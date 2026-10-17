class_name Mitigation

## Defensive mitigation applied at the moment of impact, inside
## [method SkillNode.take_damage]. Attacker says "5 PHYSICAL"; this turns it
## into the effective post-armor number that actually subtracts HP.
##
## [b]Armor pierce[/b] is the attacker's pipeline over the defender's FINAL
## armor ([member DamageInstance.armor_pierce], stamped by [method pierce_terms]):
## folded only when armor > 0, clamped at 0 (pierce never makes a hit bigger;
## breaking armor below 0 is `armor_break`'s job), floored to whole once.
## Never merged into the defender's armor bins — see docs/domain/defense-axes.md.
##
## Formula: `final = max(min_damage_taken, raw - effective_armor)`, but only when raw > 0
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
## raw, but only becomes visible once `raw - armor > min_damage_taken`. At
## raw=1 / armor=-1 / floor 3 the defender still takes 3.
##
## [b]And it cuts the other way, on purpose: a NEGATIVE net `min_damage_taken`
## makes a glancing hit HEAL the defender.[/b] [method compute] returns the
## negative number as-is and [method NodeCombat.take_damage] reclassifies the
## landing to [constant HitInstance.Kind.HEAL] (#381). That is the design, not
## an underflow to guard — `bunker_addon.tscn` authors `-5`, and the owner
## affirmed it 2026-09-04: "the whole design of sprinkling
## `-min_damage_taken` modifiers on the board is to allow to go <0 and actually
## heal from having sufficient armor / tanking low hits heals". Anything that
## clamps this at zero is deleting a mechanic; anything that DROPS such a
## landing from a render pass is the #332-shaped bug fixed in
## [ArrowVolleyCoordinator].

static func apply(raw: DamageInstance, defender: SkillNode) -> float:
	return apply_to(raw, defender.get_combat() if defender != null else null)


## The door: [method NodeCombat.take_damage] calls it for live and shadow
## nodes alike, reading the defender's stats node-locally off its slice.
static func apply_to(raw: DamageInstance, defender: NodeCombat) -> float:
	if raw.type == DamageInstance.Type.TRUE:
		return raw.amount
	if raw.amount <= 0.0:
		return 0.0
	var armor: float = 0.0
	var floor_min: float = 0.0
	if defender != null:
		armor = float(defender.get_local_value(&"armor"))
		floor_min = float(defender.get_local_value(&"min_damage_taken"))
	return compute(raw.amount, armor, floor_min, raw.armor_pierce)


## The formula itself, free of any board/node lookup. [param pierce] null is
## identity.
static func compute(amount: float, armor: float, floor_min: float, pierce: FoldTerms = null) -> float:
	if amount <= 0.0:
		return 0.0
	return max(floor_min, amount - effective_armor(armor, pierce))


## [param armor] after [param pierce]: untouched when there is no pierce or the
## armor is already ≤ 0; otherwise folded, clamped at 0 and made whole ONCE —
## `armor` is INT (ADR 0016's floor toward zero; ≥ 0 here, so `int()` is it),
## and a whole result keeps `effective` whole (ADR 0033).
static func effective_armor(armor: float, pierce: FoldTerms) -> float:
	if pierce == null or armor <= 0.0:
		return armor
	return float(int(maxf(0.0, pierce.fold(armor))))


## What a hit producer stamps on [member DamageInstance.armor_pierce]: the
## attacking node's local `armor_pierce` terms (when [param uses_board]) with
## the producer's own [param mods] overlaid through the one fold path. Null —
## no pierce — when neither contributes anything. Resolve once per attack or
## volley and share the result: it is a snapshot, so replay and the shadow
## world never see later board changes.
static func pierce_terms(read: NodeCombat, uses_board: bool, mods: Array[StatModifier]) -> FoldTerms:
	var overlays: Array[ModifierBins] = []
	if not mods.is_empty():
		var own := ModifierBins.new()
		var o := read.owner() if read != null else null
		own.board = o.board() if o != null else null
		for m in mods:
			if m != null:
				own.add(m, own.board)
		overlays.append(own)
	var t: FoldTerms
	if uses_board and read != null:
		t = read.get_local_terms(&"armor_pierce", overlays)
	elif overlays.is_empty():
		return null
	else:
		t = ModifierBins.resolve(overlays)
	if t.set_value == null and is_zero_approx(t.add) and is_zero_approx(t.inc) \
			and is_zero_approx(t.bon) and is_equal_approx(t.mult, 1.0):
		return null
	return t
