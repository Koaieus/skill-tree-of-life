class_name NodeCombat
extends RefCounted

## The live combat-state slice for a [SkillNode] (#498 step 1 — see
## docs/domain/attack-timeline.md). Holds the STATE-CHANGE half of
## take_damage / heal_damage / refill and the `is_allocated` query; the
## NOTIFICATION half (signals, [Events], presentation) stays on [member host]
## and is reached through `host.notify_*` — see those methods on [SkillNode].
##
## [member host] is assigned once, at construction, and is never reassigned —
## no public setter. Step 1 never constructs a hostless slice (that's #498
## step 2's `snapshot()`), so every method here may assume [member host] is
## non-null; the `if host != null:` guards on the notify calls exist only so
## this file does not have to change again when step 2 introduces shadows.
var host: SkillNode


func _init(p_host: SkillNode) -> void:
	host = p_host


func is_allocated() -> bool:
	return host.owned_by != null


## State half of [method SkillNode.take_damage] — see that method for the
## public contract. Mitigation, the HP pool deplete, and (for a core node)
## the overflow chip into the owner's `health` pool all happen here; the
## signal/Events/dispatch notification is [method SkillNode.notify_damaged],
## and the depleted announcement is [method SkillNode.notify_depleted].
func take_damage(amount: float, source: Variant) -> void:
	if host.owned_by == null or amount <= 0.0:
		return
	var raw: DamageInstance
	if source is DamageInstance:
		raw = source
	else:
		raw = DamageInstance.new()
		raw.amount = amount
	var effective: float = Mitigation.apply(raw, host)
	# #381: a defensive `min_damage_taken` underflow (Bulwark-style) can push
	# `effective` negative — that's a real heal, not a damage number that
	# happened to round to nothing. Reclassify BEFORE the presentation layer
	# reads `kind`. `effective == 0` stays DAMAGE — a real hit that soaked to
	# nothing.
	var flipped_to_heal := source is DamageInstance and effective < 0.0
	if flipped_to_heal:
		(source as DamageInstance).kind = HitInstance.Kind.HEAL
	var hp := host.node_board.get_stat(&"node_health") as PoolStat if host._node_board_ready else null
	if hp == null:
		return
	var before := hp.current
	hp.deplete(effective)
	if source is DamageInstance:
		if flipped_to_heal:
			# Clamped delta's magnitude — same contract heal_damage uses, so a
			# flipped hit's reveal shows what actually landed on the pool.
			(source as DamageInstance).effective_amount = absf(hp.current - before)
		else:
			# Pre-#381 contract, unchanged: the post-mitigation number, NOT the
			# post-soak delta — an overkill/core hit must still report the full
			# mitigated amount, or a killing blow's floater under-reports.
			(source as DamageInstance).effective_amount = effective
	var soaked: float = before - hp.current
	if soaked > 0.0:
		# D-9: any actual HP loss marks this node "damaged since last
		# upkeep" — apply_turn_regen() reads and clears this at turn start.
		host._damaged_since_upkeep = true
	if host != null:
		host.notify_damaged(before, hp.current, effective, source)
	# Re-read owned_by fresh (not cached) — a reentrant hook fired by
	# notify_damaged's dispatch could in principle have changed it, same as
	# the pre-extraction body never cached it either.
	var overflow: float = effective - soaked
	if host.owned_by.core_location == host:
		if overflow > 0.0 and host.owned_by.stat_board != null and host.owned_by.stat_board.health != null:
			# Snapshot the entity + its pool BEFORE deplete(): crossing 0 fires
			# `health.depleted` synchronously, which can run the whole death
			# cascade (die() -> ... -> AllocationSystem strips this very core
			# node) before deplete() returns — re-reading `owned_by` afterward
			# would see it already cleared to null.
			var entity := host.owned_by
			var health_pool := entity.stat_board.health
			var entity_before := health_pool.current
			# Record BEFORE mutating (placeholder to_value, patched below) —
			# a lethal overflow re-enters through die() from inside deplete(),
			# which would otherwise record ENTITY_DEATH ahead of this event.
			var health_event := RevealRecorder.entity_health(entity, entity_before, entity_before)
			health_pool.deplete(overflow)
			health_event.to_value = health_pool.current
		return
	if hp.current <= 0.0 and host != null:
		host.notify_depleted()


## State half of [method SkillNode.heal_damage] — see that method for the
## public contract. The notification half is [method SkillNode.notify_healed].
func heal_damage(amount: float, source: Variant) -> void:
	if host.owned_by == null or amount <= 0.0:
		return
	var hp := host.node_board.get_stat(&"node_health") as PoolStat if host._node_board_ready else null
	if hp == null:
		return
	var prev := hp.current
	hp.set_current(min(hp.current + amount, hp.value))
	var effective := hp.current - prev
	# Stash the post-clamp number back onto the instance so a LATER
	# presentation reveal (heal_shown, #481/#482) can show what actually
	# landed instead of the raw pre-clamp amount.
	if source is HealInstance:
		(source as HealInstance).effective_amount = effective
	if host != null:
		host.notify_healed(prev, hp.current, effective, source)


## State half of [method SkillNode.refill]. The notification half is
## [method SkillNode.notify_refilled].
func refill(silent: bool = false) -> void:
	var hp := host.node_board.get_stat(&"node_health") as PoolStat if host._node_board_ready else null
	if hp == null:
		return
	var prev := hp.current
	hp.restore_to_full()
	if host != null:
		host.notify_refilled(prev, hp.current, silent)
