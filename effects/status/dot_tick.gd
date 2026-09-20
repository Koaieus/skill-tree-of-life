class_name DotTick
extends RefCounted

## The one tick body every damage-over-time status shares (#964, hub #952):
## mint an unmitigated [constant DamageInstance.Type.TRUE] hit and land it
## through [method DamageInstance.land_on] — the same door an attack's hit
## lands by, so `damaged` / regen-suppression / a killing `notify_depleted`
## all fire naturally, and the [enum HitInstance.AmountBasis] resolves there
## and nowhere else. [PoisonStatus] and [CorruptionStatus] are two defs over
## this single implementation, never two copies of it.


## Land [param amount] (HP for FLAT, a fraction of max hp for PERCENT_MAX)
## on [param host] — the status host, a [NodeCombat] or an [EntityCombat]
## (see the contract on [StatusHost]) — as TRUE damage. A non-positive amount
## lands nothing. `CritRoll.apply` is a no-op for a hit with no crit decided
## (multiplier 1.0) — a tick never crits.
##
## The ENTITY host (#996) mints the same TRUE [DamageInstance] — PERCENT_MAX
## resolved against `health`'s cap via the host's own `get_max_hp()` — but
## lands it through [method EntityCombat.take_pool_damage], the one
## pool-damage door (#995): no node HP in the way, and the live
## `health.depleted` / shadow `simulate_entity_death` both live behind it.
static func mint(host, amount: float, basis: HitInstance.AmountBasis) -> void:
	if amount <= 0.0:
		return
	var dmg := DamageInstance.new()
	dmg.type = DamageInstance.Type.TRUE
	dmg.basis = basis
	dmg.amount = amount
	if host is EntityCombat:
		var core: NodeCombat = host.core()
		dmg.target = core.real() if core != null else null
		# `resolve_amount` is typed on a node slice; the same basis fold
		# against the pool's cap, in place (a tick is never PERCENT_CURRENT).
		if basis == HitInstance.AmountBasis.PERCENT_MAX:
			dmg.amount *= host.get_max_hp()
			dmg.basis = HitInstance.AmountBasis.FLAT
		CritRoll.apply(dmg)
		dmg.effective_amount = dmg.amount
		host.take_pool_damage(dmg.amount, dmg)
		return
	dmg.target = host.host  # the real SkillNode behind the slice (null on a shadow)
	dmg.land_on(host, null)


## The sum of every remaining tick's damage under [param def]'s own decay
## (#962, for #953's overlay): at 20 stacks halving, 20 + 10 + 5 + 2.5 + 1.25
## = 38.75 — the 0.625 tail is cut before it ticks. PERCENT_MAX resolves
## against the node's max hp as of now. A FLAT-decay def sums its linear
## run-down the same way; a def that never decays is capped at one tick so
## the loop terminates.
static func project(def: StatusDef, host, power: float, damage_per_power: float,
		basis: HitInstance.AmountBasis) -> float:
	var total := 0.0
	var p := power
	var guard := 0
	while p > 0.0 and guard < 1000:
		total += p * damage_per_power
		var next := def.decayed(p)
		if next >= p:
			break  # non-decaying def: one tick is all we can honestly project
		p = next
		guard += 1
	if basis == HitInstance.AmountBasis.PERCENT_MAX:
		total *= host.get_max_hp()
	return total
