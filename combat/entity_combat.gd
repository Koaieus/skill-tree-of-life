class_name EntityCombat
extends RefCounted

## The live combat-state slice for an [Entity] (#498 — see
## docs/domain/attack-timeline.md). Step 1 moved exactly one thing here: the
## revoke sweep + navigator-mirror removal that [AllocationSystem.force_deallocate]
## runs on the node's *previous owner* ([method revoke_node]). Step 2 adds
## [method snapshot] — a detached SHADOW that can resolve a whole attack,
## including the forced-dealloc cascade and entity death, without touching
## [Events], [AllocationSystem], or any real [SkillNode]/[Entity].
##
## [member host] is assigned once, at construction, and is never reassigned —
## no public setter. [method snapshot] is the only hostless-slice factory and
## it takes no host argument.
##
## Ownership storage does NOT move onto this class. [member owned] / [member core]
## / [member board] are ACCESSORS: live reads through [member host] (never
## cached — [AllocationSystem] writes `node.owned_by` / mirrors the navigator
## and knows nothing of this slice, so a cached read would go stale silently);
## a shadow falls back to its own [member _owned] / [member _core] / [member _board],
## populated once at [method snapshot] and kept current by
## [method apply_cascade] — the ONLY place that mutates a shadow's
## ownership, and it updates the [NodeCombat] backpointer and the shadow
## [GraphMirror] together (never one without the other, or islanding would
## answer a set the slice itself disagrees with).
##
## Effect-hook placement rule (docs/domain/attack-timeline.md's "one boundary
## that can rot"): an [Effect] hook that changes a number belongs on
## [EntityCombat]; a hook that only tells someone belongs on the host. Step 1's
## scope was the revoke sweep's own bookkeeping, not a dispatched hook.
##
## [b]The forced-dealloc cascade is ONE driver as of #518[/b] —
## [method apply_cascade], with [method cascade_set] as its pure set query.
## Step 2 shipped a hand-written shadow twin (`force_deallocate_owned`) beside
## [method BattleSystem._on_node_depleted]; the two agreed on the deallocation
## SET and disagreed on its consequences, which is the parallel-mirrors shape
## `.claude/rules/` warns about sitting in the middle of the path #498 step 3
## resolves against. There is now one loop body, with the design's single
## sanctioned `if host != null` branch inside it selecting the STRIP VERB —
## [method AllocationSystem.force_deallocate] when live, [method _strip_one]
## when shadow. Everything around that branch (the set, the pre-strip
## `allocation_level` read, the SP wound, the `dealloc_damage` chip, the
## [DeallocEntry] record) is shared, and a shadow charges the wound and the
## chip exactly as the live path does.
##
## [b]Shadow MITIGATION parity closed in #520.[/b] [method revoke_node] is one
## body for both worlds now: it revokes the dead node's granted modifiers and
## its swapped effect-sets from [method board], drops the effects it sourced
## from [method effects], and trims [method mirror] — after which
## [method apply_cascade] dispatches `_on_node_deallocated`, so
## [method AuraEffect.recompute] rebuilds from the set the strip just shrank.
## A shadow's wave N+1 therefore resolves against POST-cascade armour, which is
## the multi-wave case #498 exists to fix.
##
## The helpers that made this look expensive ([method SkillNode.remove_entity_modifiers_from],
## [method SkillNode.clear_scaled_effect_sets]) mutate the REAL node, so a
## shadow does not call them — it calls their pure read halves
## ([method SkillNode.granted_entity_modifiers], [method SkillNode.scaled_effect_leaves])
## and removes from its OWN board. The two `_scaled_*` dictionaries on a real
## node are never written by a shadow run.
##
## [b]The live cascade's ENTRY is still the bus[/b] — `Events.skill_node_depleted`
## -> [method BattleSystem._on_node_depleted], which now only computes the VFX
## layers, emits `cascade_started`, and forwards into [method apply_cascade].
## It no longer IMPLEMENTS the cascade, which is what scope item 1 was about;
## moving the live trigger off the bus as well would mean giving this class an
## [AllocationSystem] reference, and every fixture that writes
## `node.owned_by = entity` directly (~50 test files) would silently get a
## no-op cascade. The reference is a parameter on [method apply_cascade]
## instead, supplied by whoever is driving.
##
## A caller done with a SHADOW must call [method free_shadow] on it — see
## that method for why ordinary refcounting can't do it (a reference cycle
## between this instance and its owned [NodeCombat]s).
var host: Entity

## Shadow-only backing (meaningful only when [member host] == null).
var _board: StatBoard
var _owned: Array[NodeCombat] = []
var _core: NodeCombat
## Manual-mode [GraphMirror] over the REAL [Graph] (topology never changes
## mid-attack — see docs/domain/attack-timeline.md's melee physics note), used
## only for [method nodes_islanded_by_removing] on a shadow. `wire_to` is
## never called, so [method GraphMirror._should_mirror] (the only thing that
## reads REAL ownership) is never consulted — precedent:
## `attack/plan/melee_attack_plan.gd`'s `_blade_mirror`. [GraphMirror] `extends
## Node`, so it needs an explicit free — [method free_shadow] does that (the
## primary path; see its doc for why [constant NOTIFICATION_PREDELETE] alone
## can't be relied on here, unlike the `_blade_mirror` precedent).
var _mirror: GraphMirror
## Real [SkillNode] -> shadow [NodeCombat] — needed because [member _mirror] is
## keyed by the real node (topology lives there) while every other shadow
## accessor is keyed by [NodeCombat] (ownership lives here). Built once at
## [method snapshot]; membership never shrinks, so a node stripped by
## [method apply_cascade] can still be translated afterwards.
##
## The [b]other[/b] direction is [method NodeCombat.real], not a second
## dictionary here (#498 step 3). A shadow node already had to know its real
## node to be nameable in a [DeallocEntry]; keeping a parallel map of the same
## fact is the shape `.claude/rules/` warns about, and the two could go out of
## step only in one direction — silently.
var _shadow_by_real: Dictionary[SkillNode, NodeCombat] = {}
## The [Entity] this slice stands for on a SHADOW — its IDENTITY only. Same
## contract, and the same warning, as [member NodeCombat._real]: never a back
## door to [member host]. It answers "whose territory is this" for
## [method NodeCombat.ownership_bit], which a landing gate asks on every hit.
var _origin: Entity
## Meaningful ONLY when [member host] == null — the shadow's own refcounted tag
## set. See [member NodeCombat._tags] for why tag storage, unlike ownership,
## genuinely has to move for a shadow.
var _tags: Dictionary[StringName, int] = {}
## Meaningful ONLY when [member host] == null — the shadow's stand-in for
## [member Entity._effect_instances] (#520). Populated at [method snapshot] from
## [method Entity.get_effects] via [method EffectInstance.clone_for], one twin
## per live instance, each with COPIED ledger rows and a context bound to this
## slice. Without it a shadow could strip a node's ownership but not the
## modifiers that node's effects had granted — the pre-cascade-armour divergence
## #518 shipped with and this closes.
var _effects: Array[EffectInstance] = []
## The [CombatWorld] that minted this shadow, so an [Effect] granting to a
## [SkillNode] can find that node's slice in the SAME world. Set by
## [method CombatWorld.combat_for_entity]; null on a live slice, where
## [method world] answers with the live world.
var _world: CombatWorld
## True when THIS slice minted [member _world] itself (a bare
## [method snapshot] with no world handed in), and so is the one that must tear
## it down. False for a shadow a [CombatWorld] owns — there the world outlives
## any one entity in it.
var _owns_world: bool = false


func _init(p_host: Entity = null) -> void:
	host = p_host


func _notification(what: int) -> void:
	# Defensive backstop only — see [method free_shadow] for why this rarely
	# fires. A shadow with an EMPTY owned set (no [NodeCombat] holding a
	# backpointer into it) has no cycle and DOES reach NOTIFICATION_PREDELETE
	# normally; anything with owned nodes needs the explicit call.
	if what == NOTIFICATION_PREDELETE and _mirror != null:
		_mirror.free()
		_mirror = null


## Tear down a SHADOW explicitly — the caller's job once it's done with one
## (an AI rollout between iterations, a test in `after_each`). Ordinary
## refcounting cannot do this for us: every owned [NodeCombat]'s
## [member NodeCombat._owner] backpoints at THIS instance, so a shadow entity
## and its shadow nodes form a reference CYCLE, and GDScript's [RefCounted]
## has no cycle collector — [method _notification]'s [constant NOTIFICATION_PREDELETE]
## would never fire on its own. This method breaks the cycle (clears every
## backpointer) and frees [member _mirror] (a [Node] — also never freed by
## refcounting), after which ordinary refcounting finishes the job once the
## caller drops its own reference. No-op on a LIVE slice — nothing to tear
## down; [member host] != null never entered a cycle in the first place.
##
## [b]The cloned stat boards are a SECOND cycle of the same shape[/b] (#514):
## every [Stat] backpoints at the [StatBoard] holding it, so a board dropped
## without [method StatBoard.release] is never collected either — 122 objects
## per entity board, measured, plus one node board per owned node. Releasing
## them is therefore part of this teardown, not a separate call a caller could
## forget. Done BEFORE `_owned` is cleared, which is the only order that can
## still reach each owned node's board.
func free_shadow() -> void:
	if host != null:
		return
	# Over `_shadow_by_real`, not `_owned` — a node this shadow's own cascade
	# stripped is gone from `_owned` but its cloned board is still allocated and
	# still uncollectable (#514's cycle). `_shadow_by_real` never shrinks, which
	# is what makes it the complete roster.
	for n in _shadow_by_real.values():
		if n._board != null:
			n._board.release()
			n._board = null
	if _board != null:
		_board.release()
		_board = null
	for n in _shadow_by_real.values():
		n._owner = null
		n._real = null
	_owned.clear()
	_shadow_by_real.clear()
	_core = null
	_origin = null
	_tags.clear()
	# The twins hold a context that backpoints here — a third cycle of the same
	# shape as the owned nodes and the cloned boards.
	for inst in _effects:
		inst.context = null
	_effects.clear()
	# Null the back-reference BEFORE handing back to a world we minted — that
	# call re-enters this method, and the null is what terminates it.
	var owned_world := _world if _owns_world else null
	_world = null
	_owns_world = false
	if owned_world != null:
		owned_world.free_shadow()
	if _mirror != null:
		_mirror.free()
		_mirror = null


## This entity's [StatBoard]. Live: [member Entity.stat_board], read fresh
## every call. Shadow: the deep clone made at [method snapshot].
func board() -> StatBoard:
	return host.stat_board if host != null else _board


## Every [NodeCombat] this entity owns. Live: derived from
## [member Entity.navigator] on every call (never cached, same rule as
## [method board]). Shadow: the slice's own ledger.
func owned() -> Array[NodeCombat]:
	if host != null:
		var out: Array[NodeCombat] = []
		if host.navigator != null:
			for n in host.navigator.get_mirrored_nodes():
				out.append(n.get_combat())
		return out
	return _owned.duplicate()


## This entity's core [NodeCombat]. Live: [member Entity.core_location]'s
## slice. Shadow: the slice snapshotted at [member Entity.core_location].
func core() -> NodeCombat:
	if host != null:
		# Null-guarded — GDScript has no safe-navigation operator, and
		# `core_location` genuinely is null before an entity's first
		# placement.
		return host.core_location.get_combat() if host.core_location != null else null
	return _core


## Build a detached SHADOW of this LIVE slice (only ever call on a slice with
## [member host] != null). `host` on the result is null FOREVER — see the
## class doc. Deep-clones [member Entity.stat_board] exactly like
## [method Entity._ready] does, snapshots every currently-owned [NodeCombat]
## via [method NodeCombat.snapshot], and builds the manual-mode [member _mirror]
## from the real owned set — see the class doc for why a real [SkillNode] is
## still needed for that one piece.
func snapshot(into: CombatWorld = null) -> EntityCombat:
	var shadow := EntityCombat.new()
	if host == null:
		return shadow
	# Assigned before anything on the shadow can dispatch — see [method world].
	if into != null:
		shadow._world = into
	shadow._origin = host
	if host.stat_board != null:
		# clone_live, not duplicate(true) — see its doc: a bare duplicate
		# silently drops every already-applied modifier's bins and every
		# dynamically-minted stat.
		shadow._board = host.stat_board.clone_live()
	shadow._mirror = GraphMirror.new()
	shadow._mirror.graph = host.navigator.graph if host.navigator != null else null
	# Two statements, not `… if host.navigator != null else []` — a ternary's
	# static type is the common supertype, so the empty branch is an UNTYPED
	# `Array` and assigning it to `Array[SkillNode]` is a hard runtime error on
	# exactly the null-navigator path this line exists to tolerate.
	var real_nodes: Array[SkillNode] = []
	if host.navigator != null:
		real_nodes = host.navigator.get_mirrored_nodes()
	for real_node in real_nodes:
		var node_shadow: NodeCombat = real_node.get_combat().snapshot(shadow)
		shadow._owned.append(node_shadow)
		shadow._shadow_by_real[real_node] = node_shadow
		shadow._mirror.mirror_add(real_node)
	if host.core_location != null:
		shadow._core = shadow._shadow_by_real.get(host.core_location)
	shadow._tags = host._tags.duplicate()
	# Last, so every twin's context sees a fully-populated shadow: an
	# `_on_revoked` or a recompute fired against one reads `owned()` / `core()`
	# / `mirror()` immediately.
	for inst in host.get_effects():
		shadow._effects.append(inst.clone_for(shadow))
	return shadow


## The [Entity] this slice stands for — [member host] when live,
## [member _origin] when shadow. IDENTITY only; see [member _origin]. The
## entity-level twin of [method NodeCombat.real].
func real_entity() -> Entity:
	return host if host != null else _origin


## The world this slice's state lives in — what lets an [EffectContext] resolve
## a [SkillNode] grant target to the right node slice.
##
## A shadow NEVER falls back to the live world: that fallback is exactly how an
## aura recomputing on a shadow would grant node-local modifiers to real nodes.
## A bare [method snapshot] therefore mints a private world on first ask, which
## [method free_shadow] then owns.
func world() -> CombatWorld:
	if host != null:
		return CombatWorld.live()
	if _world == null:
		_world = CombatWorld.shadow()
		_world.adopt(self)
		_owns_world = true
	return _world


## The owned-subgraph mirror to measure over: the entity's real
## [EntityNavigator] when live, this shadow's manual-mode [member _mirror] when
## not. Both are keyed by real [SkillNode]s, and both track only what this
## entity currently owns — including, on a shadow, after [method apply_cascade]
## has taken nodes out of it, which is what makes an aura recompute against a
## shadow read the POST-cascade set (#520).
func mirror() -> GraphMirror:
	return host.navigator if host != null else _mirror


## The refcounted tag dictionary to read and write — the entity-wide twin of
## [method NodeCombat._tag_store].
func _tag_store() -> Dictionary[StringName, int]:
	return host._tags if host != null else _tags


func add_tag(tag: StringName) -> void:
	var store := _tag_store()
	store[tag] = store.get(tag, 0) + 1


func remove_tag(tag: StringName) -> void:
	var store := _tag_store()
	var count: int = store.get(tag, 0) - 1
	if count <= 0:
		store.erase(tag)
	else:
		store[tag] = count


func has_tag(tag: StringName) -> bool:
	return _tag_store().get(tag, 0) > 0


## Every [EffectInstance] currently attached to this entity — the live ledger
## when live, the shadow twins when not.
func effects() -> Array[EffectInstance]:
	return host.get_effects() if host != null else _effects.duplicate()


## Detach one effect, reverting every modifier and tag it granted. Live hands
## back to [method Entity.revoke_effect], which also keeps the hook buckets; a
## shadow has no buckets (it dispatches by walking [member _effects]) so it runs
## the `_on_revoked` hook and drops the row.
func revoke_effect(inst: EffectInstance) -> void:
	if inst == null:
		return
	if host != null:
		host.revoke_effect(inst)
		return
	if not _effects.has(inst):
		return
	inst.effect._on_revoked(inst.context)
	_effects.erase(inst)


## Revoke every effect [param source_node] granted — the deallocation path.
## Iterates a copy: `_on_revoked` may revoke re-entrantly.
func revoke_effects_from(source_node: SkillNode) -> void:
	if host != null:
		host.revoke_effects_from(source_node)
		return
	for inst in _effects.duplicate():
		if inst.source_node == source_node:
			revoke_effect(inst)


## Fire [param hook] on every effect that implements it. Live goes through
## [method Entity.dispatch] (hook buckets, so it costs nothing per unimplemented
## hook); a shadow walks its own small ledger, which is the same set without the
## index. This is how [method AuraEffect.recompute] is reached after a cascade
## changes what this entity owns.
func dispatch(hook: StringName, args: Array = []) -> void:
	if host != null:
		host.dispatch(hook, args)
		return
	for inst in _effects.duplicate():
		if inst.effect == null or not inst.effect.implemented_hooks().has(hook):
			continue
		var call_args: Array = [inst.context]
		call_args.append_array(args)
		inst.effect.callv(hook, call_args)


## This shadow's real -> shadow node index, for a [CombatWorld] assembling
## several entities' slices into one board-wide lookup. Empty on a live slice
## (there is nothing to index — [method SkillNode.get_combat] already is the
## lookup). Handed out directly rather than copied: [CombatWorld] folds it into
## its own dictionary and never mutates this one.
func shadow_index() -> Dictionary[SkillNode, NodeCombat]:
	return _shadow_by_real


## All [NodeCombat]s that would lose reachability to [param anchor] if
## [param node] were removed — the slice-scoped twin of
## [method GraphMirror.nodes_islanded_by_removing]. Live delegates straight to
## [member Entity.navigator] (already exact); a shadow answers off
## [member _mirror], translating through [member _shadow_by_real] /
## [method NodeCombat.real] at the boundary since the mirror itself is keyed
## by the real [SkillNode].
func nodes_islanded_by_removing(node: NodeCombat, anchor: NodeCombat) -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	if node == null or anchor == null:
		return out
	if host != null:
		if host.navigator == null or node.host == null or anchor.host == null:
			return out
		for n in host.navigator.nodes_islanded_by_removing(node.host, anchor.host):
			out.append(n.get_combat())
		return out
	if _mirror == null:
		return out
	var real_node: SkillNode = node.real()
	var real_anchor: SkillNode = anchor.real()
	if real_node == null or real_anchor == null:
		return out
	for rn in _mirror.nodes_islanded_by_removing(real_node, real_anchor):
		var shadow_n: NodeCombat = _shadow_by_real.get(rn)
		if shadow_n != null:
			out.append(shadow_n)
	return out


## The nodes a depletion of [param node] takes with it: [param node] itself
## plus everything [method nodes_islanded_by_removing] reports off it. PURE —
## it strips nothing and charges nothing, which is what lets
## [method BattleSystem._on_node_depleted] BFS the set into VFX layers and emit
## `cascade_started` BEFORE the world changes under the coordinator reading it.
##
## Must be answered before the strip either way: removing the depleted node
## from the navigator mirror first would make its own islanded set go stale.
func cascade_set(node: NodeCombat) -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	if node == null or node.owner() != self:
		return out
	out.append(node)
	out.append_array(nodes_islanded_by_removing(node, core()))
	return out


## [b]The one cascade driver[/b] (#518). Strips every node in [param nodes]
## from this entity and charges what leaving costs: one SP wound and one
## `dealloc_damage` chip per node, both scaled by the PRE-strip
## `allocation_level`. Returns a [DeallocEntry] per node actually stripped —
## the record a [HitInstance] carries and a peer replays.
##
## Three callers, one loop body:
##   * [method BattleSystem._on_node_depleted] — live, passing its own
##     [param alloc]; the set comes from [method cascade_set].
##   * [method NodeCombat.take_damage] — shadow, via [method cascade_from].
##   * a peer replaying an [AttackRecord] — the set arrives RECORDED rather
##     than derived, which is the whole point of recording it (a fogged client
##     cannot walk the defender's navigator to re-derive one).
##
## [param alloc] is required on a LIVE slice and ignored on a shadow. A live
## call without one strips nothing and returns empty rather than half-applying:
## [method AllocationSystem.force_deallocate] owns `owned_by`, the
## `_on_node_deallocated` dispatch and the `force_deallocated` signal that
## [AllocationVFX] draws from, and reimplementing those here is exactly the
## second implementation this method exists to delete.
##
## [param charge] is the one knob, and it exists to MATCH the live path rather
## than to add a mode: [method AllocationSystem.deallocate_all_owned] (death
## cleanup) force-deallocates without wounding or chipping — an entity already
## at 0 health is not further attrited — while the battle cascade does both.
## [method simulate_entity_death] is the only caller that passes false.
func apply_cascade(nodes: Array[NodeCombat], alloc: AllocationSystem = null,
		charge: bool = true) -> Array[DeallocEntry]:
	var entries: Array[DeallocEntry] = []
	if nodes.is_empty():
		return entries
	var b := board()
	# Read once, applied per cascaded node. Older hand-authored boards lacking
	# the stat fall back to the StatDef default (1).
	var hp_per_node: float = 1.0
	var dealloc_stat: Stat = b.get_stat(&"dealloc_damage") if b != null else null
	if dealloc_stat != null:
		hp_per_node = float(dealloc_stat.get_value())
	for n in nodes:
		# Re-checked per node, never hoisted — the live twin's
		# `if n.owned_by != defender: continue` guard, kept. The chip below can
		# cross the owner's `health` 0 mid-loop, which fires `Events.entity_died`
		# -> [method AllocationSystem.deallocate_all_owned] RE-ENTRANTLY and
		# strips the rest of the set from under us. Without this, the nodes it
		# already took would be wounded and chipped for a second time.
		if n == null or n.owner() != self:
			continue
		var entry := DeallocEntry.new()
		entry.node = real_node_for(n)
		entry.node_id = entry.node.stable_id if entry.node != null else 0
		# PRE-strip, always — see [member DeallocEntry.allocation_level] for the
		# #337 collapse this ordering exists to avoid.
		entry.allocation_level = maxi(n.get_allocation_level(), 1)
		entry.wound = entry.allocation_level
		entry.chip = hp_per_node * float(entry.allocation_level) if hp_per_node > 0.0 else 0.0
		entry.was_core = core() == n
		entry.revoked_labels = _granted_labels(entry.node)
		# ── The one branch: which strip verb. Everything else is shared. ──
		if host != null:
			if alloc == null:
				continue
			alloc.force_deallocate(n.host)
		else:
			# The same three steps `force_deallocate` performs, in its order
			# (#520): revoke sweep, then ownership, then the dealloc hook — and
			# it is that hook which re-runs AuraEffect.recompute against the set
			# this strip just shrank, so wave N+1 resolves against POST-cascade
			# armour rather than pre-cascade armour.
			revoke_node(entry.node)
			_strip_one(n)
			dispatch(&"_on_node_deallocated", [entry.node, true])
		if b != null and charge:
			var sp := b.get_stat(&"skill_points") as SkillPointStat
			if sp != null:
				sp.wound(entry.wound)
			if entry.chip > 0.0:
				# get_stat, not the typed `.health` field — `board()` reads as
				# the base [StatBoard] here (see [method NodeCombat.take_damage]
				# for the same read and why).
				var health_pool := b.get_stat(&"health") as PoolStat
				if health_pool != null:
					# #504: the core bar draws `health` directly and hears its
					# `current_changed`, so the chip announces itself — nothing
					# to record or patch for presentation.
					health_pool.deplete(entry.chip)
		entries.append(entry)
	return entries


## [method cascade_set] + [method apply_cascade] in one call — the shadow's
## entry point, reached from [method NodeCombat.take_damage] when a non-core
## node's HP crosses 0. A shadow's `notify_depleted` is never called
## (`host == null`), so `Events.skill_node_depleted` never fires and nothing
## would drive the cascade otherwise. The live path splits the two halves
## instead, because its VFX layers must be announced between them.
func cascade_from(node: NodeCombat, alloc: AllocationSystem = null) -> Array[DeallocEntry]:
	return apply_cascade(cascade_set(node), alloc)


## Strip every node this entity owns — the whole-entity sweep, run on a SHADOW
## when its core `health` pool crosses 0 (see [method NodeCombat.take_damage]'s
## overflow branch). Goes through [method apply_cascade] like everything else,
## so a simulated entity death charges its wounds and chips too; the live twin
## is [method AllocationSystem.deallocate_all_owned].
##
## "Recursive" in the sense the acceptance criteria mean it: a core hit can
## chip `health` to 0, which strips the whole owned set in one sweep — there is
## nothing left to recurse into after that.
func simulate_entity_death() -> Array[DeallocEntry]:
	var entries := apply_cascade(_owned.duplicate(), null, false)
	_core = null
	return entries


## The real [SkillNode] behind [param n]. Topology is the real graph either way
## (see [method snapshot]), so a shadow's entries can still name the node they
## stripped, which is what lets a [DeallocEntry] cross the wire. Kept as a
## method on this class for its callers' sake; the fact itself now lives on the
## node slice ([method NodeCombat.real]).
func real_node_for(n: NodeCombat) -> SkillNode:
	return n.real() if n != null else null


## Display names of the modifiers [param node] grants its owner — the
## presentation half of a [DeallocEntry], for the client's "modifier lost"
## toast. A pure READ: #518 does not revoke a shadow's grants at all (that is
## #520), and reading names is the part that could ship without mutating the
## real node.
static func _granted_labels(node: SkillNode) -> PackedStringArray:
	var out := PackedStringArray()
	if node == null:
		return out
	for m: StatModifier in node.modifiers:
		if m != null:
			out.append(m.resource_name if not m.resource_name.is_empty() else str(m.stat_id))
	return out


func _strip_one(node: NodeCombat) -> void:
	if node == null or not _owned.has(node):
		return
	_owned.erase(node)
	node._owner = null
	var real: SkillNode = node.real()
	if real != null and _mirror != null:
		_mirror.mirror_remove(real)


## Strip [param node]'s footprint from this entity: swapped effect-sets, granted
## effects, entity-scoped modifiers, and the navigator mirror. Called by
## [method AllocationSystem.force_deallocate] on the node's previous owner,
## before ownership clears — and, since #520, by [method apply_cascade] on the
## shadow side of its one branch, so shadow MITIGATION parity now holds the way
## #518 made shadow ATTRITION parity hold.
##
## One body, two worlds, and the difference is only which board is written and
## which mirror is trimmed:
## [codeblock]
##   swapped effect-set leaves  ->  board()      (via SkillNode.scaled_effect_leaves)
##   effects sourced at node    ->  effects()    (live ledger / shadow twins)
##   node's granted modifiers   ->  board()      (via granted_entity_modifiers)
##   node                       ->  mirror()
## [/codeblock]
##
## The two `_scaled_*` dictionaries on the real [SkillNode] are the one thing a
## shadow must NOT touch, which is why this reads them through the pure
## accessors and leaves the `erase` to [method SkillNode.remove_entity_modifiers_from]
## on the live path. A shadow run therefore leaves every real node's
## [code]_scaled_sets[/code] / [code]_scaled_effect_sets[/code] and every real
## entity's effect ledger byte-identical.
func revoke_node(node: SkillNode) -> void:
	if node == null:
		return
	var b := board()
	if b != null:
		# Strip swapped effect-sets BEFORE the revoke sweep — the set leaves were
		# applied outside the effect ledger and would strand otherwise (#376).
		if host != null:
			node.clear_scaled_effect_sets(b)
		else:
			# Same removal, aimed at the shadow's board. Not
			# `clear_scaled_effect_sets`: its `_remove_leaf_set` branches on
			# `board == node_board` and would reach the real node's board.
			for leaf in node.scaled_effect_leaves():
				b.remove_modifier(leaf)
	revoke_effects_from(node)
	if b != null:
		if host != null:
			node.remove_entity_modifiers_from(b)
		else:
			b.begin_batch()
			for handle in node.granted_entity_modifiers():
				b.remove_modifier(handle)
			b.end_batch()
	var m := mirror()
	if m != null:
		m.mirror_remove(node)
