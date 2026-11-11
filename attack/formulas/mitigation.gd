class_name Mitigation

## Defensive mitigation applied at the moment of impact, inside [method
## NodeCombat.take_damage]: `final = max(min_damage_taken, raw - effective_armor)`
## for raw > 0; TRUE damage bypasses it. Both stats are read node-locally. A
## NEGATIVE net `min_damage_taken` makes a glancing hit HEAL the defender, on
## purpose (owner 2026-09-04) -- never clamp it at zero.
## See docs/domain/hit-resolution.md "Mitigation".

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
