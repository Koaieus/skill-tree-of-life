class_name CombatWorld
extends RefCounted

## The world an [AttackOutcome] lands in: the one lookup that turns the
## [SkillNode] a hit NAMES (its identity, unchanged) into the [NodeCombat] it
## MUTATES. [method live] serves the real world; [method shadow] grows
## per-entity and per-node slices on demand and must be released with
## [method free_shadow]. See docs/domain/hit-resolution.md "Landing against
## a world: CombatWorld".

## Live only: once per world turn, at the end of [method flow_temperature] —
## [param changed] is every [NodeCombat] whose terrain the pass moved (the union
## of its [method TerrainSettle.commit] results, each node once). The terrain
## bars' spread cue (#1796) listens.
signal terrain_settled(changed: Array[NodeCombat])

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
## The sandpile worklist: holders whose pile may have become unstable since the
## last settle — insertion-ordered, so one Dictionary is both set and queue.
## Per world, so a shadow's dies with it. See [method note_pile].
var _piles: Dictionary = {}  # holder (NodeCombat | EntityCombat) -> true
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

	func spill_scale(n) -> float:
		return _scale.get(n, 1.0)

	func nodes() -> Array:
		return _power.keys()

	func stacks(n) -> float:
		return _power[n] if _power.has(n) else super(n)

	func masked_neighbours(n) -> Array[NodeCombat]:
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
## [SpreadApplier] call, keeping its debit-first contract. [member from] /
## [member to] are LIVE holders: a [NodeCombat], or an [EntityCombat] for a
## core pile.
class SettleOp:
	var def: StatusDef
	var key: Variant = true
	var from
	var to
	var amount: float = 0.0
	var threshold: int = 0
	var batch: int = 0


## The field [method settle_topples] hands [method SandpileSpread.stabilize]:
## seeded with the popped holders, its adjacency resolved from the world on
## first ask (a neighbour reached mid-cascade included), and a holder topples
## iff [method CombatWorld._settles]. A core pile ([EntityCombat]) borrows its
## core node's adjacency; no node lists it, so it receives only by hits.
class _SettleField:
	extends StackField
	var _world: CombatWorld
	var _seeds: Array = []

	func _init(p_world: CombatWorld, p_def: StatusDef, p_mask: int,
			p_seeds: Array, p_key: Variant) -> void:
		super(p_def, p_mask, {}, p_key)
		_world = p_world
		_seeds = p_seeds

	func nodes() -> Array:
		return _seeds.duplicate()

	func topples(n) -> bool:
		return _world._settles(n)

	func neighbours_in(n, p_mask: int) -> Array[NodeCombat]:
		if n != null and not _adjacency.has(n):
			var at: NodeCombat = n.core() if n is EntityCombat else n
			_adjacency[n] = _world._neighbours_of(at) if at != null else [] as Array[NodeCombat]
		return super(n, p_mask)


## The real world. Every lookup delegates to the live slice each object already
## composes, so this adds no state and cannot go stale.
static func live() -> CombatWorld:
	if _live == null:
		_live = CombatWorld.new()
	return _live


## Drops the live world so the next live() starts with no pending removals.
## Harness only: a run between tests, or a sandbox tab entering and leaving (tab 77), never mid-turn.
static func reset_live() -> void:
	_live = null


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


# Every LIVE node slice carrying terrain (`t != 0` or `charge > 0`, #1794) —
# kept in step by the one writer, [method NodeCombat.add_terrain], and per node
# by a snapshot decode; nothing walks the graph. #1795's world-turn pass gathers
# from it. Live-only: a shadow world refuses, since no shadow runs a world turn.

## Insertion-ordered set: [NodeCombat] -> true.
var _terrain: Dictionary = {}


## [param node] carries terrain. No-op on a shadow world.
func note_terrain(node: NodeCombat) -> void:
	if not _shadow and node != null:
		_terrain[node] = true


## [param node] carries no terrain any more.
func forget_terrain(node: NodeCombat) -> void:
	_terrain.erase(node)


## Note or forget [param node] by what its state holds now.
func reindex_terrain(node: NodeCombat) -> void:
	if node == null:
		return
	if node.terrain_t() != 0 or node.charge() > 0:
		note_terrain(node)
	else:
		forget_terrain(node)


func holds_terrain(node: NodeCombat) -> bool:
	return _terrain.has(node)


## The indexed slices, insertion order. A slice whose host is freed is dropped.
func terrain_nodes() -> Array[NodeCombat]:
	var out: Array[NodeCombat] = []
	for node: NodeCombat in _terrain.keys():
		if is_instance_valid(node.host):
			out.append(node)
		else:
			_terrain.erase(node)
	return out


# ── World-turn terrain pass (#1795) ──────────────────────────────────────────
#
# [method TurnManager._end_world_turn] runs [method flow_temperature] after the
# lingering ticks and before the flush: Heat/Cold diffusion steps on the signed
# t, then one decay sweep of t and Charge. Both gather from the terrain index
# above onto packed arrays (never a walk of the graph) and write only through
# [method TerrainSettle.commit]. The only implementation: no mirror. Integer
# only and roll-free. Live-only: a shadow world runs no world turn.


## One world turn's terrain: [param steps] diffusion steps, each from a fresh
## snapshot, then one decay sweep, then one [signal terrain_settled] with every
## node the pass moved (#1796). A shadow world refuses.
func flow_temperature(steps: int) -> void:
	if _shadow:
		return
	var passes: Array = []
	for _i in maxi(steps, 0):
		passes.append(diffuse_temperature())
	passes.append(decay_terrain())
	var changed: Array[NodeCombat] = []
	var seen: Dictionary = {}
	for moved: Array[NodeCombat] in passes:
		for node in moved:
			if not seen.has(node):
				seen[node] = true
				changed.append(node)
	terrain_settled.emit(changed)


## One Heat/Cold diffusion step from one snapshot (floored Metropolis,
## `docs/design/elements/terrain.md` § Temperature): every edge with an
## indexed `t != 0` end moves `⌊gap / (1 + max(deg_u, deg_v))⌋` from hot to
## cold, degree being the graph degree T reads. The flows are summed per node
## and committed as one batch, so Σt is conserved and the index's order never
## reaches the result. A gap at or below the larger degree moves nothing (the
## dead band); a self-loop moves nothing. Returns the nodes whose t moved.
func diffuse_temperature() -> Array[NodeCombat]:
	var slices: Array[NodeCombat] = []
	if _shadow:
		return slices
	var order: Dictionary = {}  # NodeCombat -> dense index
	for node in terrain_nodes():
		if node.terrain_t() != 0:
			order[node] = slices.size()
			slices.append(node)
	var hot := slices.size()
	if hot == 0:
		return slices
	# Each edge once: a hot end takes its edges to receivers; of two hot ends,
	# the earlier in the dense order takes the edge. Parallel edges each count.
	var eu := PackedInt32Array()
	var ev := PackedInt32Array()
	for i in hot:
		var real := slices[i].real()
		var graph := real.get_graph() if real != null else null
		if graph == null:
			continue
		for m in graph.get_neighbours(real):
			if m == real:
				continue
			var nb := combat_for(m)
			var j: int = order.get(nb, -1)
			if j < 0:
				j = slices.size()
				order[nb] = j
				slices.append(nb)
			elif j < hot and j < i:
				continue
			eu.append(i)
			ev.append(j)
	var n := slices.size()
	var t := PackedInt64Array()
	var deg := PackedInt32Array()
	var delta := PackedInt64Array()
	t.resize(n)
	deg.resize(n)
	delta.resize(n)
	for k in n:
		t[k] = slices[k].terrain_t()
		var r := slices[k].real()
		deg[k] = r.get_graph_degree(r.get_graph()) if r != null else 0
		delta[k] = 0
	for e in eu.size():
		var u := eu[e]
		var v := ev[e]
		var gap := t[u] - t[v]
		if gap == 0:
			continue
		@warning_ignore("integer_division")
		var q := absi(gap) / (1 + maxi(deg[u], deg[v]))
		if gap < 0:
			q = -q
		delta[u] -= q
		delta[v] += q
	var batch := TerrainSettle.Batch.new()
	for k in n:
		if delta[k] != 0:
			batch.add_net_t(slices[k], delta[k])
	return TerrainSettle.commit(batch)


## The decay sweep: every indexed node's t one rate toward zero and its Charge
## one rate down, the rate [method TerrainSettle.decay_rate] reads (the band's,
## or the element's own at or below T). Heat and Cold read Fire / Ice by t's
## sign; Charge reads Lightning. Every rate is read before any write (one
## snapshot), so a node past the cap loses the overflow's whole rate even
## where that ends it below the cap. Charge never flows. Returns the nodes
## whose ints moved.
func decay_terrain() -> Array[NodeCombat]:
	var none: Array[NodeCombat] = []
	if _shadow:
		return none
	var heat := TerrainSettle.element_on(Terrain.Axis.HEAT)
	var cold := TerrainSettle.element_on(Terrain.Axis.COLD)
	var charge := TerrainSettle.element_on(Terrain.Axis.CHARGE)
	var batch := TerrainSettle.Batch.new()
	for node in terrain_nodes():
		var t := node.terrain_t()
		if t != 0:
			batch.add_toward_zero_t(node, TerrainSettle.decay_rate(node, heat if t > 0 else cold))
		if node.charge() > 0:
			batch.add_charge(node, -TerrainSettle.decay_rate(node, charge))
	return TerrainSettle.commit(batch)


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
	_piles.clear()
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
# Every ownership loss in this world feeds [method note_removed] through the
# one strip atom, [method EntityCombat.strip_node] — a death or force (cause
# DEATH) or a voluntary dealloc (cause DEALLOC) — and
# the beat that caused it calls [method flush_removals] once at its end, so the
# spill rule sees the beat's whole removed union: a node stripped in the same
# beat never receives. The beats: one dealloc command, one `schedule_index`
# group in [method OutcomeApplier.apply], one spell wave, one turn-end tick
# step (before its diffusion sweep). See docs/domain/status-effects.md.


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
	# Read for every stripped node, spreading rows or not: a neighbour holding
	# a pile may now sit at its lowered T.
	var neighbours := _neighbours_of(node)
	for m in neighbours:
		note_pile_if_held(m)
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


## True while removals noted on this world await the beat's
## [method flush_removals]. Outside a beat that is a bug: the spill lands late.
func has_pending_removals() -> bool:
	return not _pending.is_empty()


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
## the next round re-stabilizes on them (the phased settle). `burn ≥ 1` bounds
## it; [member settle_round_cap] is a bug alarm, not semantics.
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
	settle_visits = 0
	settle_rounds = 0
	if not _fed.is_empty() or not _fed_settle.is_empty():
		_land_recorded()
	else:
		var rounds := 0
		while true:
			_spill_pending(rounds > 0)
			if not settle_topples():
				break
			rounds += 1
			settle_rounds = rounds
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
		var from_real: SkillNode = t.from.real()
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
## uncomputed; the piles they (or the landings) enqueued stay on the worklist
## for the next computing flush.
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
			var host = _resolve(op.from)
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
			list.append(StackTransfer.new(_resolve(t.from), _resolve(t.to), t.amount, t.key))
			i += 1
		SpreadApplier.apply(def, list, self)
	_pending.clear()
	_tracked.clear()


## A recorded LIVE holder as this world's slice: a node through
## [method combat_for], a core pile through [method combat_for_entity].
func _resolve(holder):
	if holder == null:
		return null
	if holder is EntityCombat:
		return combat_for_entity(holder.real_entity())
	return combat_for(holder.real())


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
# Every beat ends here (the tail of [method flush_removals]). Settle drains a
# worklist of piles that may have become unstable — never a walk over owned
# nodes — so a beat with no sandpile movement costs nothing. Enqueued by a
# settling row rising ([method note_pile], via the host contract's
# `_on_pile_rose`) and by a degree event on a holder ([method note_pile_if_held]:
# a removal, a gate flip, a core move). See docs/domain/status-effects.md.


## [param holder]'s pile may topple: check it at the next computing flush.
## Idempotent. A replay beat computes nothing, so an entry simply waits.
## A holder is a [NodeCombat] or an entity's core pile ([EntityCombat]).
func note_pile(holder) -> void:
	if holder != null:
		_piles[holder] = true


## A degree event touched [param holder]: enqueue it only if it holds a
## settling row, so a corruption-free territory's dealloc visits nothing. A
## core NODE's event reaches its entity's core pile too (same adjacency).
func note_pile_if_held(holder) -> void:
	if holder == null:
		return
	if holder is NodeCombat and holder.is_core():
		note_pile_if_held(holder.owner())
	for row in holder.get_statuses():
		if row != null and row.def != null and row.def.spread != null \
				and row.def.spread.settles() and row.power > 0:
			_piles[holder] = true
			return


## One settle round: take the whole worklist (inserts during the round land in
## the next one), and per settling row `(def.id, key)` the popped live holders
## carry ([method _settles]), one [method SandpileSpread.stabilize] seeded with
## them at the CURRENT degrees; land the transfers (each receiver re-enqueues
## itself through the hook — the next round finds it stable), then one
## [method StatusDef._on_burst] per toppled host (its damage is a normal hit,
## so a depletion notes a removal). Returns whether anything toppled. Two piles
## stand at a core: its node's rows topple like any node's, and the entity's
## own rows (fallen through a cracked core) are a second holder over the core
## node's masked neighbours minus itself; its burst hits the entity's pool.
func settle_topples() -> bool:
	if _piles.is_empty():
		return false
	var popped: Array = _piles.keys()
	_piles.clear()
	settle_visits += popped.size()
	var rows := {}     # [id, key] -> StatusDef
	var holders := {}  # [id, key] -> Array of holders
	for h in popped:
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
		var result := spread.stabilize(
				_SettleField.new(self, def, spread.ownership_mask, holders[rid], rid[1]))
		if result.topples.is_empty():
			continue
		toppled = true
		_record_batch(def, result.transfers)
		SpreadApplier.apply(def, result.transfers, self)
		for n in result.topples:
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


## A holder that topples here: an allocated node (the core node too), or a
## living entity standing on a core (its core pile).
func _settles(n) -> bool:
	if n is EntityCombat:
		return n.is_allocated() and n.core() != null and n.real_entity() != null
	return n != null and n.real() != null and n.is_allocated()


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


func _record_burst(def: StatusDef, key: Variant, n, count: int, t: int) -> void:
	if _recording == null:
		return
	var op := SettleOp.new()
	op.def = def
	op.key = key
	op.from = _live_slice(n)
	op.amount = float(count)
	op.threshold = t
	_recording.settle.append(op)


## [param n]'s LIVE holder — a record outlives its shadow: a node's real
## node's slice, an entity holder's real entity's.
static func _live_slice(n):
	if n == null:
		return null
	if n is EntityCombat:
		var e: Entity = n.real_entity()
		return e.get_combat() if e != null else null
	var real: SkillNode = n.real()
	return real.get_combat() if real != null else null
