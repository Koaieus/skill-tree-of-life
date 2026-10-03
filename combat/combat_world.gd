class_name CombatWorld
extends RefCounted

## The world an [AttackOutcome] lands in (#498 step 3 — see
## docs/domain/attack-timeline.md). One indirection, and the whole of what
## `resolve_against(slice)` turned out to mean for the landing half: every
## [method HitInstance.land_on] takes a [NodeCombat], and this is what turns the
## [SkillNode] a hit NAMES into the [NodeCombat] it MUTATES.
##
## [codeblock]
## real launch / peer replay:  OutcomeApplier.apply(outcome, CombatWorld.live(), clock)
## AI scoring / preview:       OutcomeApplier.apply(outcome, CombatWorld.shadow(), clock)
## [/codeblock]
##
## [b]Why [member HitInstance.target] stays a [SkillNode].[/b] A hit's target is
## its IDENTITY — what [AttackRecord] serializes, what a fogged peer resolves by
## `stable_id`, what every VFX observer reads. Retyping it would have made the
## shadow visible to a dozen files that have no business knowing one exists.
## State is the thing that must be swappable, so the swap lives here, in one
## lookup, and identity is left alone.
##
## [b]Why one class rather than a per-entity slice.[/b] An attack — a propagating
## spell above all — crosses territory belonging to several entities, and a
## [method EntityCombat.snapshot] is per-entity by construction. This holds as
## many of those as the attack turns out to touch, plus ownerless slices for the
## unallocated nodes a spell only uses as conduits, under one
## [SkillNode] -> [NodeCombat] index.
##
## [b]A shadow grows on demand, and that is safe.[/b] [method shadow] starts
## empty. The first time a hit lands on a node whose owner is not snapshotted
## yet, that owner's [EntityCombat] is snapshotted then — its entity board, its
## owned-set mirror, its effect twins and its core's board — and from #695 on
## each further owned NODE's board is cloned only when this world is first asked
## about that node ([method EntityCombat.shadow_for]). Snapshotting late reads
## the same state as snapshotting up front, because a shadow resolve never
## writes to the real world, so the real world is frozen for its whole duration.
## Lazily is also strictly cheaper: at ~0.7 ms per entity board (the bench on
## #498) only the entities actually hit are paid for, and at ~0.1 ms per node
## board only the nodes a walk actually visits (#681 measured 8-24 ms per hover
## for the whole-subgraph clone this replaced).
##
## Per-node laziness ends the moment anything ENTITY-wide runs — a cascade, a
## simulated death, a hook dispatch, an `owned()` read — at which point
## [method EntityCombat._materialize_all] mints the rest, so #498's "do not
## reach-bound the owned subgraph" still holds: a node fifty hops away is in the
## cascade set exactly as before, because by the time a cascade set is asked for
## the whole subgraph is present (owner call on #695, 2026-08-31).
##
## [b]Every shadow needs [method free_shadow][/b], for the reference cycles
## [method EntityCombat.free_shadow] documents. A live world holds nothing and
## frees nothing.

## Live singleton — stateless, so one instance serves every caller and the
## default argument on [method OutcomeApplier.apply] costs no allocation.
static var _live: CombatWorld = null

## True for a world backed by shadow slices. The one thing outside this class
## that reads it is the melee pop cue ([BladePopResolver.LiveGate]) — an
## announcement, which a shadow must not make, exactly like [member SkillNode]'s
## `host != null` branch.
var _shadow: bool = false
var _nodes: Dictionary[SkillNode, NodeCombat] = {}
var _entities: Dictionary[Entity, EntityCombat] = {}
## Ownerless slices minted for unallocated conduit nodes — held apart from
## [member _entities] because no [EntityCombat] will release their boards.
var _orphans: Array[NodeCombat] = []
## The removal collector: one [_Removal] per node stripped since the last
## [method flush_removals], in strip order.
var _pending: Array[_Removal] = []
## Entries a fresh landing produced since the last flush, by their real node:
## the flush writes each computed transfer onto its `from`'s entry, which is
## how an attack's spill gets into its [AttackRecord].
var _tracked: Dictionary[SkillNode, DeallocEntry] = {}
## Entries a rebuilt record handed in since the last flush. Non-empty makes the
## beat a replay: the flush lands their recorded spill and computes nothing.
var _fed: Array[DeallocEntry] = []


## One stripped node as it stood at its strip: per spreading def, the stacks
## it held and its masked neighbours. Snapshotted because by flush time its
## rows are released and its owner cleared, so the live reads say 0 and NEUTRAL.
class _Removal:
	var node: NodeCombat
	var cause: int
	# Keyed by the row's identity `[def.id, key]` (#1343): a spill is per row.
	var defs: Dictionary = {}    # [StringName, key] -> StatusDef
	var power: Dictionary = {}   # [StringName, key] -> float
	var around: Dictionary = {}  # [StringName, key] -> Array[NodeCombat]


## The field a flush hands [method StatusSpread.on_removed]: a removed node
## answers [method stacks] and [method masked_neighbours] from its pre-strip
## snapshot (its host is empty and ownerless by now); any other node reads
## live through [StackField].
class _RemovalField:
	extends StackField
	var _power: Dictionary = {}   # NodeCombat -> float
	var _around: Dictionary = {}  # NodeCombat -> Array[NodeCombat]

	func snap(n: NodeCombat, p: float, around: Array[NodeCombat]) -> void:
		_power[n] = p
		_around[n] = around

	func nodes() -> Array[NodeCombat]:
		var out: Array[NodeCombat] = []
		out.assign(_power.keys())
		return out

	func stacks(n: NodeCombat) -> float:
		return _power[n] if _power.has(n) else super(n)

	func masked_neighbours(n: NodeCombat) -> Array[NodeCombat]:
		if _around.has(n):
			var out: Array[NodeCombat] = []
			out.assign(_around[n])
			return out
		return super(n)


## The real world. Every lookup delegates to the live slice each object already
## composes, so this adds no state and cannot go stale.
static func live() -> CombatWorld:
	if _live == null:
		_live = CombatWorld.new()
	return _live


## A detached world. Nothing is snapshotted until something is asked for — see
## the class doc on why growing on demand is both safe and cheaper.
static func shadow() -> CombatWorld:
	var w := CombatWorld.new()
	w._shadow = true
	return w


func is_lingering(_node: NodeCombat) -> bool:
	return false


func is_shadow() -> bool:
	return _shadow


## The [NodeCombat] that [param node]'s state lives in for this world.
##
## Live: the node's own composed slice. Shadow: the snapshot, taken now if this
## is the first time this world has been asked about [param node] — and its
## owner's entity-level snapshot too, if this is the first of that owner's
## nodes (see the class doc). An unallocated node gets an ownerless slice of
## its own — a spell conduit has no entity to snapshot, but it still has a
## board a hit could read or mutate.
func combat_for(node: SkillNode) -> NodeCombat:
	if node == null:
		return null
	if not _shadow:
		return node.get_combat()
	var known: NodeCombat = _nodes.get(node)
	if known != null:
		return known
	var owner_entity := node.owned_by
	if owner_entity != null:
		# Mints just THIS node's board (#695) — `shadow_for` registers it here
		# through `index_node`. Null when the owner's navigator disagrees with
		# `owned_by` (a fixture that wrote the field directly), which falls
		# through to an orphan exactly as the whole-subgraph fold did.
		known = combat_for_entity(owner_entity).shadow_for(node)
		if known != null:
			return known
	var orphan := node.get_combat().snapshot(self)
	# Un-owned: an orphan exists because `owned_by` disagrees with the owner's
	# navigator, and resolving it would snapshot that entity for a node it
	# does not hold.
	orphan._state.owned_by = null
	_nodes[node] = orphan
	_orphans.append(orphan)
	return orphan


## The [EntityCombat] that [param entity]'s state lives in for this world.
## Shadow: snapshotted on first ask; its owned nodes join this world's node
## index one at a time as they are minted ([method index_node]).
func combat_for_entity(entity: Entity) -> EntityCombat:
	if entity == null:
		return null
	if not _shadow:
		return entity.get_combat()
	var known: EntityCombat = _entities.get(entity)
	if known != null:
		return known
	# `self` is handed IN rather than assigned after: an EffectContext resolves a
	# SkillNode grant target through its slice's world, and a snapshot's effect
	# twins are live from the moment they exist.
	var shadow_entity := entity.get_combat().snapshot(self)
	adopt(shadow_entity)
	return shadow_entity


## Register an already-built shadow [EntityCombat] and fold the nodes it has
## minted so far into this world's index. Called by [method combat_for_entity],
## and by [method EntityCombat.world] when a bare snapshot mints its own world —
## the case that needs the fold: nodes minted before the shadow had a world to
## [method index_node] into.
func adopt(shadow_entity: EntityCombat) -> void:
	if shadow_entity == null or not _shadow:
		return
	var origin := shadow_entity.real_entity()
	if origin != null:
		_entities[origin] = shadow_entity
	var index := shadow_entity.shadow_index()
	for real_node in index:
		index_node(real_node, index[real_node])


## Index one minted shadow node under its real node. Called by
## [method EntityCombat.shadow_for] as it mints (#695), so a node's slice is
## findable from this world the moment it exists — an [EffectContext] resolves a
## grant target through here.
func index_node(real_node: SkillNode, slice: NodeCombat) -> void:
	if real_node == null or slice == null or not _shadow:
		return
	# An owned node can never have been minted as an orphan first —
	# `combat_for` checks `owned_by` before it orphans, and ownership does
	# not change under a shadow except by a cascade, which only ever un-owns.
	_nodes[real_node] = slice


## Release every slice this world minted. Mandatory on a shadow (see
## [method EntityCombat.free_shadow] for the [RefCounted] cycles involved) and a
## no-op on the live world, which minted nothing.
func free_shadow() -> void:
	if not _shadow:
		return
	_pending.clear()
	_tracked.clear()
	_fed.clear()
	# Taken and cleared FIRST: EntityCombat.free_shadow hands a world it minted
	# itself back to this method, so re-entry has to find nothing left to do.
	var entities: Array = _entities.values()
	_entities.clear()
	for shadow_entity in entities:
		shadow_entity.free_shadow()
	for orphan in _orphans:
		if orphan._state.board != null:
			orphan._state.board.release()
			orphan._state.board = null
			orphan._state.board_ready = false
		orphan._world = null
		orphan._real = null
	_orphans.clear()
	_entities.clear()
	_nodes.clear()


# ── Removal collector ────────────────────────────────────────────────────────
#
# Every ownership loss in this world feeds [method note_removed] — a cascade
# strip (cause DEATH, [method EntityCombat.apply_cascade]) or a voluntary
# dealloc (cause DEALLOC, [method AllocationSystem._deallocate_unchecked]) — and
# the beat that caused it calls [method flush_removals] once at its end, so the
# spill rule sees the beat's whole removed union: a node stripped in the same
# beat never receives. The beats: one dealloc command, one `schedule_index`
# group in [method OutcomeApplier.apply], one spell wave, one turn-end tick
# step (before its diffusion sweep). See docs/domain/effect-system.md.


## Record that [param node] is leaving its owner, with the [param rows]
## [method NodeCombat.release_statuses] just took off it. Call BEFORE the strip
## clears ownership: the masked-neighbour snapshot reads the node's owner.
## Every stripped node is recorded, spreading rows or not — it belongs to the
## union either way. A def with a null [member StatusDef.spread] pays nothing.
func note_removed(node: NodeCombat, rows: Array[NodeStatus], cause: int) -> void:
	if node == null:
		return
	var r := _Removal.new()
	r.node = node
	r.cause = cause
	var neighbours: Array[NodeCombat] = []
	var gathered := false
	for row in rows:
		var def := row.def if row != null else null
		if def == null or def.spread == null:
			continue
		if not gathered:
			neighbours = _neighbours_of(node)
			gathered = true
		var probe := StackField.new(def, def.spread.ownership_mask, {node: neighbours})
		var rid := [def.id, row.key]
		r.defs[rid] = def
		r.power[rid] = row.power
		r.around[rid] = probe.masked_neighbours(node)
	_pending.append(r)


## [param entries] were produced by a fresh landing on this world: the next
## flush writes the spill it computes onto them ([member DeallocEntry.spill]).
func track_entries(entries: Array[DeallocEntry]) -> void:
	for e in entries:
		if e != null and e.node != null:
			_tracked[e.node] = e


## [param entries] arrive from a rebuilt record: the next flush is a replay
## beat and lands their recorded spill instead of computing any.
func feed_recorded(entries: Array[DeallocEntry]) -> void:
	_fed.append_array(entries)


## Run the spill rule over everything noted since the last flush: per cause,
## per row `(def.id, key)`, one [method StatusSpread.on_removed] over the whole removed union,
## landed through [SpreadApplier] in this world. Loops until nothing new was
## noted, should a landing itself strip a node. Each computed transfer is also
## written onto its `from`'s tracked [DeallocEntry] ([method track_entries]).
##
## A beat fed a record ([method feed_recorded]) RECEIVES instead: it lands
## exactly the recorded transfers and computes nothing. Removals with no
## [DeallocEntry] — a whole-entity death's strips, inside the beat whose chip
## killed it — are never recorded. That is world-identical under the only
## authored mask, Mine: the dying entity's whole territory is in the beat's
## union, so every Mine transfer it could compute is burned. A rule with a
## wider-than-Mine mask must get those strips recorded first.
func flush_removals() -> void:
	if not _fed.is_empty():
		_land_recorded()
		return
	while not _pending.is_empty():
		var batch := _pending
		_pending = []
		var removed: Array[NodeCombat] = []
		var by_cause := {}  # cause -> {[id, key] -> StatusDef}, first seen
		for r in batch:
			removed.append(r.node)
			var defs: Dictionary = by_cause.get_or_add(r.cause, {})
			for rid: Array in r.defs:
				if not defs.has(rid):
					defs[rid] = r.defs[rid]
		for cause: int in by_cause:
			var rows: Dictionary = by_cause[cause]
			for rid: Array in rows:
				var def: StatusDef = rows[rid]
				var field := _RemovalField.new(def, def.spread.ownership_mask, {}, rid[1])
				for r in batch:
					if r.cause == cause and r.power.has(rid):
						field.snap(r.node, r.power[rid], r.around[rid])
				var transfers := def.spread.on_removed(field, removed, cause)
				_record_spill(def, transfers)
				SpreadApplier.apply(def, transfers, self)
	_tracked.clear()


## Writes [param transfers] onto their `from`'s tracked entry, re-pointed at
## the REAL nodes' live slices: an entry outlives its shadow (freed once the
## record is captured), exactly as [member DeallocEntry.node]
## is the real node.
func _record_spill(def: StatusDef, transfers: Array[StackTransfer]) -> void:
	if _tracked.is_empty():
		return
	for t in transfers:
		if t == null or t.from == null:
			continue
		var from_real := t.from.real()
		var e: DeallocEntry = _tracked.get(from_real)
		if e == null:
			continue
		var to_real: SkillNode = t.to.real() if t.to != null else null
		e.spill.append(StackTransfer.new(from_real.get_combat(),
				to_real.get_combat() if to_real != null else null, t.amount, t.key))
		e.spill_defs.append(def)


## A replay beat: land every fed entry's recorded transfers, per def, in this
## world's slices; the noted removals are dropped uncomputed.
func _land_recorded() -> void:
	var by_def := {}  # StatusDef -> Array[StackTransfer]
	for e in _fed:
		for k in e.spill.size():
			var t := e.spill[k]
			var def := e.spill_defs[k] if k < e.spill_defs.size() else null
			if t == null or def == null:
				continue
			var from := combat_for(t.from.real()) if t.from != null else null
			var to := combat_for(t.to.real()) if t.to != null else null
			var list: Array = by_def.get_or_add(def, [] as Array[StackTransfer])
			list.append(StackTransfer.new(from, to, t.amount, t.key))
	_fed.clear()
	_pending.clear()
	_tracked.clear()
	for def: StatusDef in by_def:
		SpreadApplier.apply(def, by_def[def], self)


## [param node]'s graph neighbours as slices of this world — the topology is
## the real graph either way, read through the owner's mirror.
func _neighbours_of(node: NodeCombat) -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	var owner_slice := node.owner()
	var mirror := owner_slice.mirror() if owner_slice != null else null
	var real := node.real()
	if mirror == null or mirror.graph == null or real == null:
		return out
	for m in mirror.graph.get_neighbours(real):
		out.append(combat_for(m))
	return out
