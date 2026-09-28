class_name HitPoints

## The one rounding rule for health (ADR 0017): HP and every quantity that
## adds to or subtracts from it are whole numbers, so a magnitude is floored
## (truncated toward zero) ONCE, where it lands on a pool — the four doors
## [method NodeCombat.take_damage], [method NodeCombat.heal_damage],
## [method EntityCombat.take_pool_damage] and [method EntityCombat.heal]. Not
## inside [Mitigation]: replayed [AttackRecord] hits and DoT ticks land as TRUE
## damage and never pass through it. A sub-1 magnitude lands 0; when that
## zeroes something the design wanted to matter, fix the authored value, never
## a carry or a ceiling. Returned as a float so storage and call sites keep
## their types; same truncation as an INT stat's `Stat._coerce`.


static func land(amount: float) -> float:
	return float(int(amount))
