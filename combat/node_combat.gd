class_name NodeCombat
extends RefCounted

## The live combat-state slice for a [SkillNode] (#498 — see
## docs/domain/attack-timeline.md). Holds the STATE-CHANGE half of
## take_damage / heal_damage / refill and the `is_allocated` query; the
## NOTIFICATION half (signals, [Events], presentation) stays on [member host]
## and is reached through `host.notify_*` — see those methods on [SkillNode].
##
## [member host] is assigned once, at construction, and is never reassigned —
## no public setter. Two constructors populate it:
## - [method _init], for a LIVE slice: `host` is the real [SkillNode].
## - [method snapshot], for a SHADOW: `host` is null forever, and every method
##   below branches on that null exactly once (`if host != null:` — never a
##   second, preview-specific branch). Ownership and board storage do NOT
##   move onto this class even for a shadow — [member owner] / [member board]
##   are ACCESSORS that read through [member host] when live and fall back to
##   [member _owner] / [member _board] only when it's null. Reading through
##   `host` on every call (never caching) is deliberate: [AllocationSystem]
##   writes `node.owned_by` directly and knows nothing about this slice, so a
##   cached owner would go stale silently the moment it does.
var host: SkillNode
## Meaningful ONLY when [member host] == null (a shadow). Set once, by
## [method snapshot], never reassigned afterward.
var _owner: EntityCombat
## Meaningful ONLY when [member host] == null (a shadow) — the shadow's own
## deep-cloned [NodeStatBoard], standing in for [member SkillNode.node_board].
var _board: NodeStatBoard


func _init(p_host: SkillNode = null) -> void:
	host = p_host


## The owning [EntityCombat] slice. Live: [code]host.owned_by.get_combat()[/code],
## read fresh every call — see the class doc's no-caching rule. Shadow: the
## `_owner` set once by [method snapshot].
func owner() -> EntityCombat:
	if host != null:
		# Null-guarded, not a bare `host.owned_by.get_combat()` — GDScript has
		# no safe-navigation operator, and an unallocated live node's
		# `owned_by` genuinely is null (that's what `is_allocated() == false`
		# means), so calling straight through would crash on every
		# unallocated read instead of just answering "no owner".
		return host.owned_by.get_combat() if host.owned_by != null else null
	return _owner


## This node's [NodeStatBoard]. Live: [member SkillNode.node_board] (only once
## [member SkillNode._node_board_ready] — a lazily-materialized board that
## hasn't minted yet reads as absent, same as every other node_board read in
## this file). Shadow: the deep clone made at [method snapshot].
func board() -> NodeStatBoard:
	if host != null:
		return host.node_board if host._node_board_ready else null
	return _board


func is_allocated() -> bool:
	return owner() != null


## True iff this is its owner's core node. Live: the same
## `owned_by.core_location == host` check [method take_damage] always ran.
## Shadow: the equivalent question against the shadow's own [member EntityCombat.core].
func is_core() -> bool:
	var o := owner()
	return o != null and o.core() == self


## Build a detached shadow of this LIVE slice (see the class doc — never call
## on a slice that is already a shadow), owned by [param owner_combat].
## `host` on the result is null FOREVER. Deep-clones [member SkillNode.node_board]
## exactly like [method SkillNode._init_node_board] clones the authored
## template, so the shadow gets its own [PoolStat] with the live current/max —
## "real PoolStat semantics", not a captured float.
func snapshot(owner_combat: EntityCombat) -> NodeCombat:
	var shadow := NodeCombat.new()
	shadow._owner = owner_combat
	if host != null:
		host._init_node_board()
		# clone_live, not duplicate(true) — see its doc on StatBoard.
		shadow._board = host.node_board.clone_live() as NodeStatBoard
	return shadow


## Non-allocating passthrough read — the state-half twin of
## [method SkillNode.get_local_value], which now delegates here (#498 step 2).
## Merges this node's board with its owner's, exactly as before; the only
## change from the pre-extraction body is reading [method board] / [method owner]
## instead of `node_board` / `owned_by.stat_board` directly, which is what
## makes it correct on a shadow too (needed by [method take_damage]'s
## mitigation math — see [Mitigation], which requires a real [SkillNode] and
## so cannot be called on a shadow's behalf).
func get_local_value(stat_id: StringName) -> Variant:
	var ns: Stat = board().get_stat(stat_id) if board() != null else null
	var o := owner()
	if o != null and o.board() != null:
		var es := o.board().get_stat(stat_id)
		if es != null:
			if ns == null:
				return es.get_value()
			var sources: Array[ModifierBins] = [es.bins, ns.bins]
			return ModifierBins.compute(es.base_value, sources)
	if ns != null:
		return ns.get_value()
	var def: StatDef = StatRegistry.get_def(stat_id)
	if def != null:
		return def.default_value
	return 0.0


## Max combat HP — state-half twin of [method SkillNode.get_max_hp]. Live
## reads the node board's pool, which [method SkillNode._sync_combat_health_base]
## keeps ratcheted (PUSH, off the owner's `node_health` `value_changed` signal)
## — untouched here. A shadow has no host, so no [SkillNode] and no signal to
## drive that push; it re-runs the identical ratchet formula on every read
## instead (PULL). That's what lets a modifier added to the shadow's own
## entity board move the cap mid-"attack" with no signal machinery in play —
## see docs/domain/attack-timeline.md's "max health is derived, not snapshotted".
func get_max_hp() -> float:
	var b := board()
	if b == null:
		return 0.0
	var hp := b.get_stat(&"node_health") as PoolStat
	if hp == null:
		return 0.0
	if host == null:
		var o := owner()
		var baseline: Stat = o.board().get_stat(&"node_health") if o != null and o.board() != null else null
		if baseline != null:
			hp.set_base_ratcheted(float(baseline.get_value()))
	return hp.value


## This node's fill — state-half twin of [member SkillNode.allocation_level],
## and the number a forced deallocation's SP wound and `dealloc_damage` chip
## both scale by ([method EntityCombat.apply_cascade]).
##
## Works identically on a shadow because `allocation_level` is not a field: it
## reads `node_board.stake_level.current` (`skill_node/skill_node.gd:350-352`),
## a [PoolStat] on the node board, and a shadow holds its own [method StatBoard.clone_live]
## of that board. So the cascade's pre-strip read needs no live [SkillNode] —
## which is what let scope item 3 of #518 ship without one.
func get_allocation_level() -> int:
	var b := board()
	if b == null:
		return 0
	var stake := b.get_stat(&"stake_level") as PoolStat
	return int(stake.current) if stake != null else 0


## Current combat HP — state-half twin of [method SkillNode.get_current_hp].
func get_current_hp() -> float:
	var b := board()
	if b == null:
		return 0.0
	var hp := b.get_stat(&"node_health") as PoolStat
	return hp.current if hp != null else 0.0


## State half of [method SkillNode.take_damage] — see that method for the
## public contract. Mitigation, the HP pool deplete, and (for a core node)
## the overflow chip into the owner's `health` pool all happen here; the
## signal/Events/dispatch notification is [method SkillNode.notify_damaged],
## and the depleted announcement is [method SkillNode.notify_depleted] —
## both reached ONLY when [member host] != null, which is the one branch this
## whole design has (see the class doc). A depleted SHADOW node instead calls
## [method EntityCombat.cascade_from] directly: there is no
## [Events] bus reach for it to fall through to, by construction.
func take_damage(amount: float, source: Variant) -> void:
	var o := owner()
	if o == null or amount <= 0.0:
		return
	var raw: DamageInstance
	if source is DamageInstance:
		raw = source
	else:
		raw = DamageInstance.new()
		raw.amount = amount
	var effective: float
	if host != null:
		effective = Mitigation.apply(raw, host)
	else:
		# Mitigation.apply requires a real SkillNode (it reads defensive stats
		# via SkillNode.get_local_value) — a shadow has none. Mitigation.compute
		# is the free-standing formula half of the same file; feed it the
		# armor/floor read through THIS class's own get_local_value instead.
		if raw.type == DamageInstance.Type.TRUE:
			effective = raw.amount
		else:
			var armor: float = get_local_value(&"armor")
			var floor_min: float = get_local_value(&"min_damage_taken")
			effective = Mitigation.compute(raw.amount, armor, floor_min)
	# #381: a defensive `min_damage_taken` underflow (Bulwark-style) can push
	# `effective` negative — that's a real heal, not a damage number that
	# happened to round to nothing. Reclassify BEFORE the presentation layer
	# reads `kind`. `effective == 0` stays DAMAGE — a real hit that soaked to
	# nothing.
	var flipped_to_heal := source is DamageInstance and effective < 0.0
	if flipped_to_heal:
		(source as DamageInstance).kind = HitInstance.Kind.HEAL
	var hp := board().get_stat(&"node_health") as PoolStat if board() != null else null
	if hp == null:
		return
	var before := hp.current
	hp.deplete(effective)
	if source is HitInstance:
		# The health BAR's numbers, deliberately distinct from the FLOATER's
		# `effective_amount` below — on an overkill they always disagree, and
		# reconciling them into one number is a bug. See
		# [member HitInstance.hp_before].
		var hit := source as HitInstance
		hit.hp_before = before
		hit.hp_after = hp.current
		hit.hp_max = get_max_hp()
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
	if soaked > 0.0 and host != null:
		# D-9: any actual HP loss marks this node "damaged since last
		# upkeep" — apply_turn_regen() reads and clears this at turn start.
		# Regen upkeep is a per-turn, host-only concern; a shadow never sees a
		# turn boundary, so there is nothing for it to gate.
		host._damaged_since_upkeep = true
	if host != null:
		host.notify_damaged(before, hp.current, effective, source)
	# Re-read the owner fresh (not cached) — a reentrant hook fired by
	# notify_damaged's dispatch could in principle have changed it, same as
	# the pre-extraction body never cached `owned_by` either.
	o = owner()
	var overflow: float = effective - soaked
	if is_core():
		if overflow > 0.0:
			var ent_board := o.board()
			# get_stat, not a typed `.health` field access — `board()` reads as
			# the base `StatBoard` (a shadow's board doesn't get the narrower
			# `EntityStatBoard` static type), and `health` only exists there.
			var health_pool := ent_board.get_stat(&"health") as PoolStat if ent_board != null else null
			if health_pool != null:
				# Snapshot BEFORE deplete(): crossing 0 fires `health.depleted`
				# synchronously on a LIVE board, which can run the whole death
				# cascade before deplete() returns. A shadow's duplicated
				# `health` PoolStat carries no such signal connection (Resource
				# duplicate() doesn't copy runtime signal connections) — its
				# equivalent is the explicit `current <= 0.0` check below.
				health_pool.deplete(overflow)
				if host == null and health_pool.current <= 0.0:
					o.simulate_entity_death()
		return
	if hp.current <= 0.0:
		if host != null:
			# Presentation + the live cascade's ENTRY: the bus handler
			# ([method BattleSystem._on_node_depleted]) announces the VFX
			# layers and then forwards into the SAME
			# [method EntityCombat.apply_cascade] the shadow reaches below
			# (#518). It no longer implements a cascade of its own.
			#
			# Synchronous, so `source.deallocations` is populated by the time
			# this returns — the handler records the entries back onto the hit
			# it was handed. That is why the signal carries `source` at all.
			host.notify_depleted(source)
		else:
			# A shadow has no bus to fall through to, so it records its own.
			var entries := o.cascade_from(self)
			if source is HitInstance:
				(source as HitInstance).deallocations = entries


## State half of [method SkillNode.heal_damage] — see that method for the
## public contract. The notification half is [method SkillNode.notify_healed].
func heal_damage(amount: float, source: Variant) -> void:
	if owner() == null or amount <= 0.0:
		return
	var hp := board().get_stat(&"node_health") as PoolStat if board() != null else null
	if hp == null:
		return
	var prev := hp.current
	hp.set_current(min(hp.current + amount, hp.value))
	var effective := hp.current - prev
	# Stash the post-clamp number back onto the instance so a consumer reading
	# the hit afterward (AI scoring, an outcome summary) sees what actually
	# landed instead of the raw pre-clamp amount.
	if source is HealInstance:
		(source as HealInstance).effective_amount = effective
	if host != null:
		host.notify_healed(prev, hp.current, effective, source)


## State half of [method SkillNode.refill]. The notification half is
## [method SkillNode.notify_refilled].
func refill(silent: bool = false) -> void:
	var hp := board().get_stat(&"node_health") as PoolStat if board() != null else null
	if hp == null:
		return
	var prev := hp.current
	hp.restore_to_full()
	if host != null:
		host.notify_refilled(prev, hp.current, silent)
