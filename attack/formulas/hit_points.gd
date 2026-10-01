class_name HitPoints

## The one rounding rule for health (ADR 0017, ADR 0033): HP and every
## quantity that adds to or subtracts from it are whole numbers, so a damage or
## heal magnitude is rounded UP (toward the larger whole number, sign kept)
## ONCE, at entry to one of the four doors — [method NodeCombat.take_damage],
## [method NodeCombat.heal_damage], [method EntityCombat.take_pool_damage] and
## [method EntityCombat.heal] — and, for damage, BEFORE [Mitigation]. Entry is
## ADR 0033's "where produced": every multiply that makes the number
## (`damage_scale`, crit, a DoT's max-HP fold, a spell's per-hop scale,
## `healing_received`) has already run, and none runs after. `armor` and
## `min_damage_taken` are INT, so mitigation is int-on-int and its result —
## a negative-floor heal included — is whole with no second rounding. A
## magnitude of exactly 0 stays 0 ([method Mitigation.compute]'s gate keeps
## it there); any positive one lands at least 1 before mitigation. Idempotent
## on wholes, so replayed [AttackRecord] amounts and a core's overflow pass
## unchanged. Float noise on a whole (`0.1 * 30`) counts as that whole, never
## a fraction to round up. Returned as a float so storage and call sites keep
## their types. See docs/domain/rounding.md.


static func whole(amount: float) -> float:
	var m := absf(amount)
	var r := roundf(m)
	return signf(amount) * (r if is_equal_approx(m, r) else ceilf(m))
