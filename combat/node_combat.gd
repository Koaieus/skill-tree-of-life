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
## The real [SkillNode] this slice stands for, on a SHADOW — its IDENTITY, never
## its state. Set once by [method snapshot], read through [method real].
##
## [b]This is not a back door to [member host].[/b] The whole host-null invariant
## is that a shadow cannot notify, and that stays true: nothing in this file
## reaches `_real` for a `notify_*`, a signal, or a board. It exists because a
## shadow still has to be able to NAME the node it stripped — [DeallocEntry.node]
## is a real [SkillNode] on a shadow cascade today (#518) for exactly this reason,
## and a wire record naming shadow objects would be meaningless. Reads that
## legitimately go through it are static facts of the real world that no attack
## mutates: topology, and the addon roster ([method get_spike_power]).
var _real: SkillNode
## Meaningful ONLY when [member host] == null (a shadow). Set once, by
## [method snapshot], never reassigned afterward.
var _owner: EntityCombat
## Meaningful ONLY when [member host] == null (a shadow) — the shadow's own
## deep-cloned [NodeStatBoard], standing in for [member SkillNode.node_board].
var _board: NodeStatBoard
## Meaningful ONLY when [member host] == null — the shadow's own refcounted tag
## set (#520). Storage, unlike ownership, genuinely has to move for a shadow:
## an [Effect] recomputing against one grants and revokes tags, and there is no
## real node those may land on. Live reads go straight to
## [member SkillNode._tags] through [method _tag_store], so there is still only
## one tag dictionary per real node.
var _tags: Dictionary[StringName, int] = {}


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
	shadow._real = host
	if host != null:
		shadow._tags = host._tags.duplicate()
		host._init_node_board()
		# clone_live, not duplicate(true) — see its doc on StatBoard.
		shadow._board = host.node_board.clone_live() as NodeStatBoard
		# The clone's `node_health` pool must resolve through the SHADOW's owner,
		# never the live one. `base_provider` is not exported so `duplicate()`
		# does not carry it, but `clone_live` copies stat-by-stat — clear it
		# explicitly rather than rely on that, then let `_hp_pool` reinstall this
		# slice's own on first read.
		var shadow_hp := shadow._board.get_stat(&"node_health") as PoolStat
		if shadow_hp != null:
			shadow_hp.base_provider = Callable()
	return shadow


## The real [SkillNode] behind this slice — [member host] when live,
## [member _real] when shadow. The slice's IDENTITY, in one accessor, so a
## caller never has to know which kind it is holding. [EntityCombat] keeps only
## the real -> shadow direction now; this is the way back.
func real() -> SkillNode:
	return host if host != null else _real


## Exactly one [enum SkillNode.Ownership] bit for this node's relation to
## [param viewer] — the slice-side home of the question, which
## [method SkillNode.ownership_bit] now delegates to so a landing gate asks it
## the same way live and shadow (`.claude/rules/ownership-vocabulary.md`).
##
## [param viewer] stays a real [Entity]: attitude is a fact about the two real
## entities, not about a slice, and a shadow's owner still knows which entity it
## shadows ([method EntityCombat.real_entity]).
func ownership_bit(viewer: Entity) -> int:
	var o := owner()
	if o == null:
		return SkillNode.Ownership.NEUTRAL
	var owner_entity := o.real_entity()
	if owner_entity == null:
		return SkillNode.Ownership.NEUTRAL
	if owner_entity == viewer:
		return SkillNode.Ownership.MINE
	if viewer != null and viewer.attitude_to(owner_entity) == Entity.Attitude.ALLIED:
		return SkillNode.Ownership.ALLY
	return SkillNode.Ownership.HOSTILE


## Defensive spike magnitude — read at melee land time by
## [BladePopResolver.LiveGate]. Delegates to the real node on a shadow too,
## deliberately: [method SkillNode.get_spike_power] sums the local modifiers of
## the [SpikeRingAddon]s attached to the node, and [b]addons are not combat
## state[/b] — no attack attaches or detaches one mid-swing. Same standing
## assumption as melee's physics exemption ("nothing moves nodes mid-attack",
## docs/domain/attack-timeline.md); a mechanic that adds or removes an addon
## during an attack breaks both together.
func get_spike_power() -> float:
	var n := real()
	return n.get_spike_power() if n != null else 0.0


## Non-allocating passthrough read — the state-half twin of
## [method SkillNode.get_local_value], which now delegates here (#498 step 2).
## Merges this node's board with its owner's, exactly as before; the only
## change from the pre-extraction body is reading [method board] / [method owner]
## instead of `node_board` / `owned_by.stat_board` directly, which is what
## makes it correct on a shadow too (needed by [method take_damage]'s
## mitigation math — see [Mitigation], which requires a real [SkillNode] and
## so cannot be called on a shadow's behalf).
##
## Also understands #333's accessor tokens — `<stat_id>__<accessor>`, e.g.
## `node_health__current` — which route to [method _read_accessor] below
## instead of the merge. A bare id behaves exactly as it always has.
func get_local_value(stat_id: StringName) -> Variant:
	if StatFormula.is_accessor_token(stat_id):
		return _read_accessor(stat_id)
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


## Reads an accessor token (`<stat_id>__<accessor>`) off whichever board owns
## the state — the #333 grammar, taught to this method rather than reimplemented
## anywhere (#702). Adds no grammar: [StatFormula]'s statics split the token and
## [method Stat.read_accessor] dispatches through the per-subclass
## [method Stat.accessors] map, so a new accessor on a new [Stat] subclass
## reaches every caller of this method for free.
##
## [b]Deliberately does NOT merge.[/b] The bin merge above is meaningful for a
## modifier-computed cap, where the entity's and the node's modifiers genuinely
## stack. It is meaningless for `.current` / `wounded` / `surplus`, which are
## ephemeral state living on exactly ONE [Stat] instance — merging two boards'
## bins onto one of them would compute a number nothing stores.
##
## So this resolves rather than merges, node board first: a node's own
## `node_health` [PoolStat] holds its damage, and only the owner's board holds
## an entity-scope pool like `skill_points`. That ordering is why
## `skill_points__wounded` works here with no further code — it simply misses
## the node board and finds the owner's [SkillPointStat].
##
## A base id absent from both boards falls through to the def default on the
## BASE id, matching the bare-id tail above. An accessor the found stat does not
## answer to is [method Stat.read_accessor]'s call, not this method's: it warns
## once and degrades to [method Stat.get_value]. Not overridden per-caller —
## one contract, one policy — and degrading is the right answer for a ranker
## anyway, since a `0.0` would silently invert the ranking. Typos are caught at
## load time by the authored-content test, not per-read here.
func _read_accessor(token: StringName) -> Variant:
	var base := StatFormula.base_of(token)
	var s: Stat = board().get_stat(base) if board() != null else null
	if s == null:
		var o := owner()
		if o != null and o.board() != null:
			s = o.board().get_stat(base)
	if s != null:
		return s.read_accessor(StatFormula.accessor_of(token))
	var def: StatDef = StatRegistry.get_def(base)
	if def != null:
		return def.default_value
	return 0.0


## This node's `node_health` pool, with its cap PROVIDER installed (#660).
##
## The provider is the whole of the CON fan-out's replacement: the pool's cap
## base is the owner's `node_health` baseline, read live on every cap read
## instead of pushed into every owned node whenever CON moves. It is installed
## here rather than by [SkillNode] because this class is the one place that
## already abstracts live-vs-shadow ([method board] / [method owner]) — one
## provider serves both worlds, each resolving through its OWN owner, and the
## shadow's "re-run the formula on read" (docs/domain/attack-timeline.md's "max
## health is derived, not snapshotted") simply became the live path too.
##
## Re-pointed on every call rather than once: a slice is not rebound when
## [AllocationSystem] rewrites `owned_by`, and the provider closes over `self`,
## whose [method owner] read is already fresh-every-call by this class's
## no-caching rule.
func _hp_pool() -> PoolStat:
	var b := board()
	if b == null:
		return null
	# Materialised on first NEED, never on ownership: the deleted sync used to
	# mint this pool as a side effect of its per-node push, and an unowned node
	# must not pay for one across a 2500-node level (.claude/rules/skill-node-scale.md).
	# `_ensure_stat` routes through [method NodeStatBoard._mint_stat], which is
	# what makes this id a PoolStat on a node board and a ScalarStat baseline on
	# an entity board.
	var hp := (b._ensure_stat(&"node_health") if is_allocated() else b.get_stat(&"node_health")) as PoolStat
	if hp != null and hp.base_provider != _node_health_base:
		hp.base_provider = _node_health_base
	return hp


## The provider itself: the owner's `node_health` baseline, or this pool's own
## stored base when there is no owner (an unallocated node still has to answer
## [method get_max_hp] with something, and its stored base is the def default
## the mint seeded).
func _node_health_base() -> float:
	var o := owner()
	var baseline: Stat = o.board().get_stat(&"node_health") if o != null and o.board() != null else null
	if baseline != null:
		return float(baseline.get_value())
	var b := board()
	var hp: Stat = b.get_stat(&"node_health") if b != null else null
	return hp.base_value if hp != null else 0.0


## Max combat HP — state-half twin of [method SkillNode.get_max_hp]. Derived on
## read, live and shadow alike, through [method _hp_pool]'s provider (#660).
func get_max_hp() -> float:
	var hp := _hp_pool()
	return hp.value if hp != null else 0.0


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
	var hp := _hp_pool()
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
	var hp := _hp_pool()
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


## The refcounted tag dictionary to read and write — the real node's when live,
## this slice's own when shadow. One store per world, never a copy of another
## world's.
func _tag_store() -> Dictionary[StringName, int]:
	return host._tags if host != null else _tags


## State half of [method SkillNode.add_tag].
func add_tag(tag: StringName) -> void:
	var store := _tag_store()
	store[tag] = store.get(tag, 0) + 1


## State half of [method SkillNode.remove_tag].
func remove_tag(tag: StringName) -> void:
	var store := _tag_store()
	var count: int = store.get(tag, 0) - 1
	if count <= 0:
		store.erase(tag)
	else:
		store[tag] = count


func has_tag(tag: StringName) -> bool:
	return _tag_store().get(tag, 0) > 0


## State half of [method SkillNode.add_local_modifier] for the shadow's benefit
## (#520) — an [AuraEffect] recomputing against a shadow grants node-local
## modifiers, and they must land on the shadow's board.
##
## Live delegates to the node, which additionally keeps the `_local_modifiers`
## ledger (the local-scale mutator's canonical list, #376) — a shadow has no
## such mutator and no ledger to keep. What a shadow must NOT skip is the
## second half of the per-leaf step: `bind_modifier` alone registers the
## dependency and applies nothing, so the stat has to be ensured and the leaf
## attached to it, exactly as [method SkillNode.add_local_modifier] does.
func add_local_modifier(m: StatModifier) -> void:
	if m == null:
		return
	if host != null:
		host.add_local_modifier(m)
		return
	if _board == null:
		return
	var cycle := _board.cycle_from(m)
	if not cycle.is_empty():
		push_warning("NodeCombat.add_local_modifier: rejected a modifier that would close a formula dependency cycle: %s" % cycle)
		return
	for leaf in m.flatten():
		_board.bind_modifier(leaf)
		_board._ensure_stat(leaf.stat_id).add_modifier(leaf, _board)


## State half of [method SkillNode.remove_local_modifier]. Removal is by object
## identity — on a shadow the handle a caller holds is the LIVE instance, and
## [method StatBoard.remove_modifier] translates it through `_localized` (#506)
## to this board's private copy.
func remove_local_modifier(m: StatModifier) -> void:
	if m == null:
		return
	if host != null:
		host.remove_local_modifier(m)
		return
	if _board == null:
		return
	for leaf in m.flatten():
		var s: Stat = _board.get_stat(leaf.stat_id)
		if s != null:
			_board.unbind_modifier(leaf)
			s.remove_modifier(leaf, _board)


## State half of [method SkillNode.heal_damage] — see that method for the
## public contract. The notification half is [method SkillNode.notify_healed].
func heal_damage(amount: float, source: Variant) -> void:
	if owner() == null or amount <= 0.0:
		return
	var hp := _hp_pool()
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
	if source is HitInstance:
		# Symmetric with take_damage — a heal moves a bar too, and a fogged peer
		# needs the same three numbers to draw it. Skipping this here would send
		# every HealInstance across the wire as 0/0/0, which reads on the far
		# side as "no bar to draw" rather than as a bug.
		var hit := source as HitInstance
		hit.hp_before = prev
		hit.hp_after = hp.current
		hit.hp_max = get_max_hp()
	if host != null:
		host.notify_healed(prev, hp.current, effective, source)


## State half of [method SkillNode.refill]. The notification half is
## [method SkillNode.notify_refilled].
func refill(silent: bool = false) -> void:
	var hp := _hp_pool()
	if hp == null:
		return
	var prev := hp.current
	hp.restore_to_full()
	if host != null:
		host.notify_refilled(prev, hp.current, silent)
