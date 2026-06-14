class_name Mitigation

## Defensive mitigation applied at the moment of impact, inside
## [method SkillNode.take_damage]. Attacker says "5 PHYSICAL"; this turns it
## into the effective post-armour number that actually subtracts HP.
##
## Stub for now — armour / resistance stats don't exist yet. Returns the raw
## amount. Clean seam: this is the single function to evolve when defensive
## stats land. TRUE damage bypasses any future reduction here.

static func apply(raw: DamageInstance, _defender_board: StatBoard) -> float:
	if raw.type == DamageInstance.Type.TRUE:
		return raw.amount
	return raw.amount
