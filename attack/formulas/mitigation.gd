class_name Mitigation

## Defensive mitigation applied at the moment of impact, inside
## [method SkillNode.take_damage]. Attacker says "5 PHYSICAL"; this turns it
## into the effective post-armor number that actually subtracts HP.
##
## Formula: `final = max(min_damage_taken, raw - armor)`, but only when raw > 0
## (zero incoming damage stays zero — the floor only triggers on a real hit).
## TRUE damage bypasses everything.

static func apply(raw: DamageInstance, defender_board: StatBoard) -> float:
	if raw.type == DamageInstance.Type.TRUE:
		return raw.amount
	if raw.amount <= 0.0:
		return 0.0
	var armor: float = 0.0
	var floor_min: float = 0.0
	if defender_board != null:
		if defender_board.armor != null:
			armor = float(defender_board.armor.get_value())
		if defender_board.min_damage_taken != null:
			floor_min = float(defender_board.min_damage_taken.get_value())
	return max(floor_min, raw.amount - armor)
