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
## NodeCombat -> the spill scale of the hit that depleted it
## ([method mark_spill_scale]); consumed by [method note_removed].
var _spill_scale: Dictionary = {}
## The beat's recording landing ([method track_hit]); null outside a fresh
## attack's beat.
var _recording: HitInstance = null
## [SettleOp]s a rebuilt record handed in since the last flush.
var _fed_settle: Array[SettleOp] = []
var _batch_seq: int = 0
var _flushing: bool = false
## Guard on [method flush_removals]' stabilize → burst → deaths rounds; hitting
## it is a [method @GlobalScope.push_error], not a balance knob.
var settle_round_cap: int = 32
## Test-facing: holders popped off the sandpile worklist since the current
## flush began (reset at the top of [method flush_removals]).
var settle_visits: int = 0
## Test-facing: settle rounds that toppled anything since the current flush began.
var settle_rounds: int = 0


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
	var spill_scale: float = 1.0


## The field a flush hands [method StatusSpread.on_removed]: a removed node
## answers [method stacks] and [method masked_neighbours] from its pre-strip
## snapshot (its host is empty and ownerless by now); any other node reads
## live through [StackField].
class _RemovalField:
	extends StackField
	var _power: Dictionary = {}   # NodeCombat -> float
	var _around: Dictionary = {}  # NodeCombat -> Array[NodeCombat]
	var _scale: Dictionary = {}   # NodeCombat -> float, only when != 1.0

	func snap(n: NodeCombat, p: float, around: Array[NodeCombat], scale: float = 1.0) -> void:
		_power[n] = p
		_around[n] = around
		if scale != 1.0:
			_scale[n] = scale

	func spill_scale(n: NodeCombat) -> float:
		return _scale.get(n, 1.0)

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


## One step of a recorded sandpile settle, as a replay lands it: a transfer
## batch member ([member threshold] 0: [member amount] stacks [member from] →
## [member to], null burned) or a burst ([member threshold] > 0:
## [method StatusDef._on_burst] on [member from], [member amount] topples).
## Consecutive transfers with the same [member batch] land as ONE
## [SpreadApplier] call, keeping its debit-first contract.
class SettleOp:
	var def: StatusDef
	var key: Variant = true
	var from: NodeCombat
	var to: NodeCombat
	var amount: float = 0.0
	var threshold: int = 0
	var batch: int = 0


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


func is_shadow() -> bool:
	return _shadow


# ── Lingering hosts (#1344) ──────────────────────────────────────────────────
#
# Every LIVE node slice holding a `StatusDef.OnDealloc.LINGER` row, kept in step
# by the slice itself ([method NodeCombat._on_statuses_changed]) — nothing walks
# the graph. An allocated member is carried but skipped: its owner's turn end
# ticks it, and the entry is already in place for the dealloc that strands it
# (the rows are kept BEFORE ownership clears). Live-only: a shadow world refuses.

## Insertion-ordered set: [NodeCombat] -> true.
var _lingering: Dictionary = {}


## [param node] holds a `LINGER` row. No-op on a shadow world.
func note_lingering(node: NodeCombat) -> void:
	if not _shadow and node != null:
		_lingering[node] = true


## [param node] holds no `LINGER` row any more.
func forget_lingering(node: NodeCombat) -> void:
	_lingering.erase(node)


## True iff [param node] is registered AND unallocated — the hosts
## [method tick_lingering] ticks.
func is_lingering(node: NodeCombat) -> bool:
	return _lingering.has(node) and not node.is_allocated()


## One tick of every unowned lingering host — run once per WORLD turn end by
## [method TurnManager._end_world_turn] (ADR 0055), after the turnless hosts'
## ticks and before its flush. Iterates a snapshot: a tick can release a host or add another. A
## host whose node is gone is dropped.
func tick_lingering() -> void:
	for node: NodeCombat in _lingering.keys():
		if not is_instance_valid(node.host):
			_lingering.erase(node)
			continue
		if not _lingering.has(node) or node.is_allocated():
			continue
		node.tick_statuses()


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
	_fed_settle.clear()
	_recording = null
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


## [param node] was just depleted by a hit carrying [param scale]
## ([member DamageInstance.spill_scale]): its own removal, noted next, spills
## multiplied. Keyed by node, so the nodes its cascade strips stay at 1.0.
func mark_spill_scale(node: NodeCombat, scale: float) -> void:
	if node != null and scale != 1.0:
		_spill_scale[node] = scale


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
	r.spill_scale = _spill_scale.get(node, 1.0)
	_spill_scale.erase(node)
	# Read for every stripped node, spreading rows or not: on a shadow this
	# mints the neighbours, so the settle sees their degree drop.
	var neighbours := _neighbours_of(node)
	for row in rows:
		var def := row.def if row != null else null
		if def == null or def.spread == null:
			continue
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


## End the beat: run the spill rule over everything noted since the last
## flush, then [method settle_topples], and repeat while a settle round
## toppled anything — a burst kill's removals spill and change degrees, and
## the next round re-stabilizes on them (the phased settle). Bounded by
## [member settle_round_cap].
##
## Spill: per cause, per row `(def.id, key)`, one [method StatusSpread.on_removed]
## over the whole removed union, landed through [SpreadApplier] in this world.
## Loops until nothing new was noted. Each computed transfer is also written
## onto its `from`'s tracked [DeallocEntry] ([method track_entries]); a later
## round's spill (a burst kill, which no entry carries) and every settle step
## go onto the beat's recording hit ([method track_hit]) as [SettleOp]s.
##
## A beat fed a record ([method feed_recorded], [method feed_settle]) RECEIVES
## instead: it lands exactly the recorded spill and settle and computes nothing.
## Removals with no [DeallocEntry] — a whole-entity death's strips, inside the
## beat whose chip killed it — are never recorded. That is world-identical
## under the only authored spill mask, Mine: the dying entity's whole territory
## is in the beat's union, so every Mine transfer it could compute is burned.
## A rule with a wider-than-Mine mask must get those strips recorded first.
##
## Re-entrant calls (a landing inside the settle that flushes) return at once:
## the outer loop picks up whatever they noted.
func flush_removals() -> void:
	if _flushing:
		return
	_flushing = true
	if not _fed.is_empty() or not _fed_settle.is_empty():
		_land_recorded()
	else:
		var rounds := 0
		while true:
			_spill_pending(rounds > 0)
			if not settle_topples():
				break
			rounds += 1
			if rounds >= settle_round_cap:
				_spill_pending(true)
				push_error("CombatWorld: settle hit settle_round_cap (%d); pile left unsettled" % settle_round_cap)
				break
	_tracked.clear()
	_spill_scale.clear()
	_recording = null
	_flushing = false


func _spill_pending(record_ops: bool) -> void:
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
						field.snap(r.node, r.power[rid], r.around[rid], r.spill_scale)
				var transfers := def.spread.on_removed(field, removed, cause)
				_record_spill(def, transfers)
				if record_ops:
					_record_batch(def, transfers)
				SpreadApplier.apply(def, transfers, self)


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
## world's slices, then the fed [SettleOp]s in their recorded order — a batch
## through one [SpreadApplier] call, a burst through [method StatusDef._on_burst].
## The removals noted meanwhile (a replayed burst's kill included) are dropped
## uncomputed.
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
	var ops := _fed_settle
	_fed.clear()
	_fed_settle = []
	for def: StatusDef in by_def:
		SpreadApplier.apply(def, by_def[def], self)
	var i := 0
	while i < ops.size():
		var op := ops[i]
		if op == null or op.def == null:
			i += 1
			continue
		if op.threshold > 0:
			var host := combat_for(op.from.real()) if op.from != null else null
			if host != null:
				op.def._on_burst(host, int(op.amount), op.threshold)
			i += 1
			continue
		var list: Array[StackTransfer] = []
		var def := op.def
		var batch := op.batch
		while i < ops.size() and ops[i] != null and ops[i].threshold == 0 \
				and ops[i].batch == batch and ops[i].def == def:
			var t := ops[i]
			list.append(StackTransfer.new(combat_for(t.from.real()) if t.from != null else null,
					combat_for(t.to.real()) if t.to != null else null, t.amount, t.key))
			i += 1
		SpreadApplier.apply(def, list, self)
	_pending.clear()
	_tracked.clear()


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


# ── Sandpile settle ──────────────────────────────────────────────────────────
#
# Every beat ends here (the tail of [method flush_removals]), so a pile pops
# the moment anything — a landing, a spill, a degree change — pushes it to its
# threshold, with no dirty set. See docs/domain/status-effects.md.


## One settle round: per sandpile row `(def.id, key)`, [method SandpileSpread.stabilize]
## at the CURRENT degrees over every allocated, non-core holder and its
## allocated non-core neighbours, land the transfers, then one
## [method StatusDef._on_burst] per toppled host (its damage is a normal hit,
## so a depletion notes a removal). Returns whether anything toppled. The core
## never topples here: it is an absorber.
func settle_topples() -> bool:
	var rows := {}     # [id, key] -> StatusDef
	var holders := {}  # [id, key] -> Array[NodeCombat]
	for h in _sandpile_candidates():
		if not _settles(h):
			continue
		for row in h.get_statuses():
			if row == null or row.def == null or not (row.def.spread is SandpileSpread):
				continue
			if row.power <= 0.0:
				continue
			var rid := [row.def.id, row.key]
			rows[rid] = row.def
			(holders.get_or_add(rid, []) as Array).append(h)
	var toppled := false
	for rid: Array in rows:
		var def: StatusDef = rows[rid]
		var spread := def.spread as SandpileSpread
		var result := spread.stabilize(_settle_field(def, spread.ownership_mask, holders[rid], rid[1]))
		if result.topples.is_empty():
			continue
		toppled = true
		_record_batch(def, result.transfers)
		SpreadApplier.apply(def, result.transfers, self)
		for n: NodeCombat in result.topples:
			var count: int = result.topples[n]
			var t: int = result.thresholds[n]
			_record_burst(def, rid[1], n, count, t)
			def._on_burst(n, count, t)
	return toppled


## The landing whose beat this is: the first fresh hit since the last flush.
## The flush writes the beat's [SettleOp]s onto its [member HitInstance.settle].
func track_hit(hit: HitInstance) -> void:
	if hit != null and _recording == null:
		_recording = hit


## [param ops] arrive from a rebuilt record: the next flush is a replay beat.
func feed_settle(ops: Array[CombatWorld.SettleOp]) -> void:
	_fed_settle.append_array(ops)


## Slices that may hold a sandpile row. Shadow: exactly the slices it has
## minted — an unminted node kept the live world's settled stacks and degree
## (a removal mints its neighbours, a credit mints its receiver). Live: every
## entity's owned nodes.
func _sandpile_candidates() -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	if _shadow:
		out.assign(_nodes.values())
		return out
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	for e in tree.get_nodes_in_group(Entity.GROUP):
		var entity := e as Entity
		if entity == null or entity.navigator == null:
			continue
		for n in entity.navigator.get_mirrored_nodes():
			if is_instance_valid(n) and n.owned_by == entity:
				out.append(n.get_combat())
	return out


## An allocated, non-core host — the only kind that topples here.
func _settles(n: NodeCombat) -> bool:
	return n != null and n.is_allocated() and not n.is_core()


## [param holders] plus their settling neighbours, so a receiver at zero can
## topple inside the same stabilize; every field node's adjacency is its real
## graph neighbourhood (the mask filters at read time).
func _settle_field(def: StatusDef, mask: int, holders: Array, key: Variant) -> StackField:
	var adjacency := {}
	for h: NodeCombat in holders:
		if not adjacency.has(h):
			adjacency[h] = _neighbours_of(h)
	for h: NodeCombat in holders:
		for m: NodeCombat in adjacency[h]:
			if not adjacency.has(m) and _settles(m):
				adjacency[m] = _neighbours_of(m)
	return StackField.new(def, mask, adjacency, key)


func _record_batch(def: StatusDef, transfers: Array[StackTransfer]) -> void:
	if _recording == null or transfers.is_empty():
		return
	_batch_seq += 1
	for t in transfers:
		if t == null:
			continue
		var op := SettleOp.new()
		op.def = def
		op.key = t.key
		op.from = _live_slice(t.from)
		op.to = _live_slice(t.to)
		op.amount = t.amount
		op.batch = _batch_seq
		_recording.settle.append(op)


func _record_burst(def: StatusDef, key: Variant, n: NodeCombat, count: int, t: int) -> void:
	if _recording == null:
		return
	var op := SettleOp.new()
	op.def = def
	op.key = key
	op.from = _live_slice(n)
	op.amount = float(count)
	op.threshold = t
	_recording.settle.append(op)


## [param n]'s REAL node's live slice — a record outlives its shadow.
static func _live_slice(n: NodeCombat) -> NodeCombat:
	if n == null:
		return null
	var real := n.real()
	return real.get_combat() if real != null else null
