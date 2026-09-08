class_name BladePopResolver
extends RefCounted

## Defensive spike "pop" resolution (#170, budget model #778). Given the raw
## BladeHitEvents from a swing scan, decides which of the ATTACKER's own blade
## vertices are killed — and which are then severed from the driven handle and
## disintegrated.
##
## The model (see the #170 design comment, budget rule per #778):
##   - A blade vertex that sweeps into a spiked, allocated enemy node drains
##     that node's remaining `spikes` pool by the vertex's own `blunting`.
##     Remaining >= blunting: the pool depletes by blunting and the vertex
##     POPS — the vertex itself dies. Remaining < blunting: the remainder
##     drains to 0 and the vertex is NOT popped, passing through to deal
##     damage as an ordinary contact (owner: "pop only if full amount is
##     removed"). Either way the contact deals damage to NOBODY BUT the
##     defender it pops against — the spiked node itself takes none, and a
##     popping vertex's own hit never lands: [method BladeDamageInstance.land_on]
##     returns as soon as [method admit] refuses the contact, before
##     `super.land_on` (the only place damage is ever applied) runs.
##   - Killing a vertex disconnects everything downstream of it from the pivot /
##     handle. Every vertex no longer reachable from the pivot through surviving
##     edges is disintegrated (this MVP; the fun free-flight variant is #186).
##   - The pivot is exempt — popping the wielder's own handle is out of scope.
##   - An unspiked node (no `spikes` pool minted — only [SpikeRingAddon] ever
##     mints one) never pops anything, at any stake level.
##
## Result is post-hoc: it does NOT re-simulate the swing, it only marks each
## dead vertex with the time it died so callers can drop that vertex's hits from
## that moment on.
##
## [b]There is exactly one implementation of these predicates: [LiveGate].[/b]
## There used to be two — a pure `resolve()` batch pass for the AI/preview
## estimate and [LiveGate] for the real swing — and they did not agree (the
## batch pass ran its whole kill pass before its disconnection pass, so a vertex
## that disintegrated at t1 could still be recorded as a pop at t2 > t1).
## #498 step 3 retired the batch pass exactly as this file's own comment
## promised it would: the estimate now runs THIS gate against a shadow
## [CombatWorld], so the AI's shape-risk signal
## ([member AttackOutcome.thinned_nodes]) is produced by the same code that
## produces the real one, against a detached copy of the same world.

## Per-pop record. `t` is the contact time; `defender` is the spiked node that
## popped `particle_idx`; `position` is where to play the pop VFX.
## `blunting_spent` is how much of the defender's `spikes` pool this contact
## drained — always the popping vertex's full `blunting` (a partial drain
## never pops, so it never reaches [method LiveGate._kill] / mints a Pop).
class Pop extends RefCounted:
	var particle_idx: int
	var t: float
	var defender: SkillNode
	var position: Vector2
	var blunting_spent: float

	func _init(particle_idx_: int, t_: float, defender_: SkillNode, blunting_spent_: float) -> void:
		particle_idx = particle_idx_
		t = t_
		defender = defender_
		blunting_spent = blunting_spent_
		position = defender_.global_position if defender_ != null else Vector2.ZERO


## `dead_at`: particle_idx -> time it became dead (killed OR disintegrated).
## A hit by that vertex at `ev.t >= dead_at[idx]` must be dropped.
## `pops`: the killing contacts only (drive VFX / hit tracking), in time order.
class Result extends RefCounted:
	var dead_at: Dictionary = {}
	var pops: Array[Pop] = []

	func is_dead(particle_idx: int, t: float) -> bool:
		return dead_at.has(particle_idx) and t >= dead_at[particle_idx]


## The pop/disconnect gate for one swing (#502): the kill/disconnect predicates
## fed one [BladeHitEvent] at a time, in true land order, by
## [method BladeDamageInstance.land_on] as [OutcomeApplier] walks the swing's
## hits — so an earlier-in-time hit's cascade is visible to a later event's
## `is_allocated()` / ownership read. See docs/domain/attack-timeline.md.
##
## [b]Which world it reads is an argument, not a mode.[/b] Handed
## [method CombatWorld.live] it gates a live swing; handed a
## [method CombatWorld.shadow] it gates the authority's compute pass or an AI
## rollout against detached slices, running the identical predicates. There is
## no preview flag anywhere below — see [method admit].
class LiveGate extends RefCounted:
	## Accepted pops so far, in the same shape [method resolve] returns —
	## [MeleePreview] replays this post-application (#502's "Watch": the
	## preview replays the applier's ACCEPTED set, never a fresh rescan).
	var result := Result.new()
	var _state: BladeState
	var _attacker: Entity
	## The [Pop] the LAST [method admit] made, or null if it made none. Cleared
	## on entry to every [method admit], so it answers "did THIS contact pop?" —
	## which is the one thing a false return cannot say on its own (a dead
	## target and a spike pop both refuse). [BladeDamageInstance] reads it to
	## stamp [member HitInstance.popped_vertex]; see that member for why the cue
	## is recorded rather than emitted from here (#536).
	var _last_pop: Pop = null
	## particle_idx -> true for every vertex currently in `result.dead_at`
	## (killed OR disintegrated). Maintained incrementally by [method _kill]
	## (#795) rather than rebuilt from `result.dead_at` every call — it only
	## ever grows within a swing.
	var _removed: Dictionary = {}
	## vertex index -> Array[int] of neighbour indices, over `_state.edges`.
	## Built lazily on first use and cached for the rest of this swing (#795):
	## one O(E) build instead of one O(E) rescan per dequeued BFS vertex.
	var _adjacency: Dictionary = {}
	var _adjacency_built: bool = false

	## `vertex_blunting` is an OPTIONAL particle_idx -> blunting override
	## (#778), consulted BEFORE the state's own
	## [member BladeState.vertex_blunting] array. Production never passes it:
	## both blade-build call sites fill the array from each source node's
	## `get_local_value(&"blunting")`, so the [SpikeRingAddon] raise to 2
	## reaches [method admit] end to end. The dict stays as the seam for a
	## fixture that wants to pin one vertex's blunting against a hand-built
	## state it never populated. See [method _blunting_for] for the full chain.
	var _vertex_blunting: Dictionary

	func _init(state: BladeState, attacker: Entity, vertex_blunting: Dictionary = {}) -> void:
		_state = state
		_attacker = attacker
		_vertex_blunting = vertex_blunting

	## The [Pop] this gate's most recent [method admit] produced, or null.
	func last_pop() -> Pop:
		return _last_pop

	## True if `ev`'s damage should actually land right now. Call exactly
	## once per event, in true time order — mutates `result` when a contact
	## turns out to be a live pop.
	##
	## [param world] selects which world the allocation / ownership / spike
	## reads come from (#535). Required, not defaulted, for the same reason
	## [method OutcomeApplier.apply]'s is — a nullable world hides an implicit
	## live branch inside a gate whose whole job is to read one specific world.
	func admit(ev: BladeHitEvent, world: CombatWorld) -> bool:
		var w := world
		_last_pop = null
		if ev.is_edge_hit():
			return false
		if result.is_dead(ev.particle_idx, ev.t):
			return false  # already popped or disintegrated by an earlier LIVE kill
		var real_node := ev.target as SkillNode
		var node: NodeCombat = w.combat_for(real_node) if real_node != null else null
		if node == null or not node.is_allocated():
			return false  # #502: dead target, no dud — indistinguishable from a miss
		if ev.particle_idx == _state.pivot_index:
			return true  # pivot / handle is exempt from popping
		if _attacker != null and node.ownership_bit(_attacker) == SkillNode.Ownership.MINE:
			return true  # your own spike can't pop your own blade
		var pool := _spikes_pool(node)
		var remaining := float(pool.current) if pool != null else 0.0
		if remaining <= 0.0:
			return true  # unspiked, or already fully spent this swing
		var blunting := _blunting_for(ev.particle_idx)
		if remaining >= blunting:
			pool.deplete(blunting)
			_mark_spent(node, w)
			_kill(ev.particle_idx, ev.t, real_node, blunting)
			return false  # the popping contact itself deals no damage
		# Remaining < blunting: drain the remainder and let the vertex THROUGH —
		# "pop only if full amount is removed" (#778). No Pop record: the vertex
		# survives and its hit lands normally.
		pool.deplete(remaining)
		_mark_spent(node, w)
		return true

	## The defender's node-local `spikes` [PoolStat], or null if it never
	## minted one — i.e. an unspiked node ([SpikeRingAddon] is the only source,
	## see spike_ring_addon.gd). Reads through [method NodeCombat.board], so it
	## resolves to the SHADOW's own cloned board on a shadow [param node], same
	## as every other per-world board read in this file (#778 — mirrors how
	## [method NodeCombat.take_damage] already deletes per-world HP with no
	## special-casing for which world it's handed).
	static func _spikes_pool(node: NodeCombat) -> PoolStat:
		var b := node.board()
		return b.get_stat(&"spikes") as PoolStat if b != null else null

	## This gate's blunting for [param particle_idx], in priority order:
	## the caller-supplied override dict, then the state's own
	## [member BladeState.vertex_blunting] slot (what production fills), then
	## the `blunting` [StatDef]'s authored default (currently 1) for a
	## hand-built state that filled neither. A zero slot counts as unfilled —
	## blunting 0 would drain nothing and pop nothing, so no authored build
	## can produce it.
	static func _blunting_for_dict(vertex_blunting: Dictionary, particle_idx: int) -> float:
		if vertex_blunting.has(particle_idx):
			return float(vertex_blunting[particle_idx])
		var def: StatDef = StatRegistry.get_def(&"blunting")
		return float(def.default_value) if def != null else 1.0

	func _blunting_for(particle_idx: int) -> float:
		if _vertex_blunting.has(particle_idx):
			return float(_vertex_blunting[particle_idx])
		if _state != null and particle_idx < _state.vertex_blunting.size():
			var from_state := _state.vertex_blunting[particle_idx]
			if from_state > 0.0:
				return from_state
		return _blunting_for_dict({}, particle_idx)

	## Registers [param node]'s real [SkillNode] on its owner's sparse
	## turn-start refresh set (#778 — Entity._on_turn_started sweeps exactly
	## this set, never all owned nodes; see entity.gd). Gated to the LIVE world
	## ONLY: a shadow's owner is the same real [Entity] the live world would
	## resolve to, and marking through a shadow (AI scoring / preview, or the
	## authority's own compute-record pass ahead of its live replay) would leak
	## a real mutation out of a world that must not touch reality — see
	## docs/domain/attack-timeline.md. The pool DEPLETE above still runs on
	## whichever world's board [param node] resolves to; only this bookkeeping
	## step is world-gated.
	static func _mark_spent(node: NodeCombat, world: CombatWorld) -> void:
		if world.is_shadow():
			return
		var owner := node.owner()
		var entity := owner.real_entity() if owner != null else null
		if entity != null:
			entity.mark_spikes_spent(node.real())

	func _kill(particle_idx: int, t: float, defender: SkillNode, blunting_spent: float) -> void:
		result.dead_at[particle_idx] = t
		var pop := Pop.new(particle_idx, t, defender, blunting_spent)
		result.pops.append(pop)
		# #504: a spike pop is a MODEL event, announced on the mutation clock —
		# the same clock the damage, the health bar and the shatter are on. It
		# is not announced from HERE, though (#536): under #498 step 3 the
		# authority runs this gate against a SHADOW world, where an emit would
		# have no audience, and then replays its own record on the live world
		# like any peer. So the pop is RECORDED — [BladeDamageInstance] reads
		# `_last_pop` onto the hit, [AttackRecord] carries it, and
		# [method OutcomeApplier.land_one] emits it as that hit lands.
		#
		# That also gives a peer the cue, which it never used to get: the
		# animation-replay emitter this replaced could only ever fire on the
		# machine that swung.
		_last_pop = pop
		_removed[particle_idx] = true
		var reachable := BladePopResolver._reachable_from_pivot(_state, _removed, _ensure_adjacency())
		for v in _state.positions.size():
			if v == _state.pivot_index or _removed.has(v):
				continue
			if not reachable.has(v):
				result.dead_at[v] = minf(result.dead_at.get(v, INF), t)
				_removed[v] = true

	## Lazily builds, then caches, this swing's adjacency map (#795) — one
	## O(E) build total instead of one per [method _kill]/[method admit].
	func _ensure_adjacency() -> Dictionary:
		if not _adjacency_built:
			_adjacency = BladePopResolver._build_adjacency(_state)
			_adjacency_built = true
		return _adjacency

	## Explicit invalidation seam (#795, for #781): nothing in this file
	## mutates `_state.edges` mid-swing today, but #781 (bunker edge breaks)
	## will remove edges from it mid-swing. Whatever does that MUST call this
	## before the next [method admit]/[method _kill], or the cached adjacency
	## goes stale and the BFS walks edges that no longer exist. Discards the
	## cache; the next [method _kill] rebuilds it from the mutated
	## `_state.edges` on demand.
	func invalidate_adjacency() -> void:
		_adjacency = {}
		_adjacency_built = false


## `state.edges` as an undirected adjacency map: vertex index -> Array[int] of
## neighbour indices, in the same order those neighbours would be discovered
## by a linear rescan of `state.edges` for that vertex (#795 — preserves
## [method _reachable_from_pivot]'s traversal order exactly, so caching this
## instead of rescanning is behaviour-preserving, not just complexity-preserving).
static func _build_adjacency(state: BladeState) -> Dictionary:
	var adjacency: Dictionary = {}
	for e in state.edges:
		if not adjacency.has(e.x):
			adjacency[e.x] = [] as Array[int]
		if not adjacency.has(e.y):
			adjacency[e.y] = [] as Array[int]
		(adjacency[e.x] as Array[int]).append(e.y)
		(adjacency[e.y] as Array[int]).append(e.x)
	return adjacency


## BFS from the pivot over an adjacency map, skipping any vertex in `removed`.
## Returns a set (Dictionary) of reachable particle indices.
##
## `adjacency` defaults to null (untyped so a caller can omit it, as the
## characterization test does): when omitted, this builds a fresh map from
## `state.edges` — still O(V + E) for THIS call, just not amortized across a
## whole swing. [method _kill] passes its cached map instead, so a swing's
## repeated pops share the one O(E) build (#795's actual fix; see
## [method LiveGate._ensure_adjacency]).
static func _reachable_from_pivot(
		state: BladeState, removed: Dictionary, adjacency: Variant = null) -> Dictionary:
	var adj: Dictionary = adjacency if adjacency != null else _build_adjacency(state)
	var reach: Dictionary = {}
	var pivot := state.pivot_index
	reach[pivot] = true
	var queue: Array[int] = [pivot]
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		var neighbours: Array = adj.get(cur, [])
		for other in neighbours:
			if removed.has(other) or reach.has(other):
				continue
			reach[other] = true
			queue.append(other)
	return reach
