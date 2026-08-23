class_name BladePopResolver
extends RefCounted

## Defensive spike "pop" resolution (#170). Given the raw BladeHitEvents from a
## swing scan, decides which of the ATTACKER's own blade vertices are killed —
## and which are then severed from the driven handle and disintegrated.
##
## The model (see the #170 design comment):
##   - A blade vertex that sweeps into a spiked, allocated enemy node is popped:
##     the hostile node takes damage equal to the node's spike power and, at MVP
##     1/1 HP, dies on contact. It deals no damage to the node that popped it.
##   - Killing a vertex disconnects everything downstream of it from the pivot /
##     handle. Every vertex no longer reachable from the pivot through surviving
##     edges is disintegrated (this MVP; the fun free-flight variant is #186).
##   - The pivot is exempt — popping the wielder's own handle is out of scope.
##
## Result is post-hoc: it does NOT re-simulate the swing, it only marks each
## dead vertex with the time it died so callers can drop that vertex's hits from
## that moment on. Shared by MeleeAttackPlan.resolve() (headless / AI scoring)
## and MeleePreview (the live swing) so the two can't drift.

## Per-pop record. `t` is the contact time; `defender` is the spiked node that
## popped `particle_idx`; `position` is where to play the pop VFX.
class Pop extends RefCounted:
	var particle_idx: int
	var t: float
	var defender: SkillNode
	var position: Vector2
	var spike_power: float

	func _init(particle_idx_: int, t_: float, defender_: SkillNode, power_: float) -> void:
		particle_idx = particle_idx_
		t = t_
		defender = defender_
		spike_power = power_
		position = defender_.global_position if defender_ != null else Vector2.ZERO


## `dead_at`: particle_idx -> time it became dead (killed OR disintegrated).
## A hit by that vertex at `ev.t >= dead_at[idx]` must be dropped.
## `pops`: the killing contacts only (drive VFX / hit tracking), in time order.
class Result extends RefCounted:
	var dead_at: Dictionary = {}
	var pops: Array[Pop] = []

	func is_dead(particle_idx: int, t: float) -> bool:
		return dead_at.has(particle_idx) and t >= dead_at[particle_idx]


## Resolve the pop/disconnect outcome for one swing. `attacker` is whose blade
## this is — a spiked node only pops when it is allocated and NOT owned by the
## attacker (i.e. an enemy's defensive spike).
static func resolve(
		events: Array[BladeHitEvent],
		state: BladeState,
		attacker: Entity) -> Result:
	var result := Result.new()
	if state == null:
		return result
	var pivot := state.pivot_index

	# Time-order so "first contact = earliest kill" holds.
	var ordered := events.duplicate()
	ordered.sort_custom(func(a: BladeHitEvent, b: BladeHitEvent) -> bool:
		return a.t < b.t)

	# --- Kill pass: which vertices are popped, and when (earliest contact). ---
	var killed_at: Dictionary = {}  # particle_idx -> t
	for ev in ordered:
		if ev.is_edge_hit():
			continue
		if ev.particle_idx == pivot:
			continue  # pivot / handle is exempt
		if killed_at.has(ev.particle_idx):
			continue  # already killed earlier (ordered by t)
		var node := ev.target as SkillNode
		if node == null or not node.is_allocated():
			continue
		if attacker != null and node.owned_by == attacker:
			continue  # your own spike can't pop your own blade
		var power := node.get_spike_power()
		if power <= 0.0:
			continue
		killed_at[ev.particle_idx] = ev.t
		result.pops.append(Pop.new(ev.particle_idx, ev.t, node, power))

	if killed_at.is_empty():
		return result

	# --- Disconnection pass: kills sever the handle; orphans disintegrate. ---
	# Process kills earliest-first; after each, anything no longer reachable from
	# the pivot dies at that kill's time.
	var kill_order := killed_at.keys()
	kill_order.sort_custom(func(a: int, b: int) -> bool:
		return killed_at[a] < killed_at[b])

	var removed: Dictionary = {}  # particle_idx -> true (killed or disintegrated)
	for k in kill_order:
		var t_k: float = killed_at[k]
		result.dead_at[k] = t_k
		removed[k] = true
		var reachable := _reachable_from_pivot(state, removed)
		for v in state.positions.size():
			if v == pivot or removed.has(v):
				continue
			if not reachable.has(v):
				result.dead_at[v] = minf(result.dead_at.get(v, INF), t_k)
				removed[v] = true
	return result


## Incremental sibling of [method resolve] (#502): the SAME kill/disconnect
## predicates, but fed one [BladeHitEvent] at a time, in true land order, by
## [BladeDamageInstance.land_on] as [OutcomeApplier] walks a real swing's
## hits. [method resolve] is pure and runs before anything lands, so its
## `node.is_allocated()` / `owned_by` reads see the pre-swing world for every
## event uniformly — correct for the up-front AI/preview estimate
## ([member AttackOutcome.thinned_nodes]), wrong for the real swing, where an
## earlier-in-time hit's cascade can deallocate a LATER event's target before
## that event lands. [LiveGate] closes that gap by reading live state at the
## instant each event actually consumes. See docs/domain/attack-timeline.md.
##
## [b]This class and [method resolve] are two implementations of the same
## predicates, and that is deliberate but TRANSITIONAL.[/b] They are not quite
## interchangeable today — [method resolve] runs its kill pass fully before
## its disconnection pass, so a vertex that disintegrates at t1 can still be
## recorded as a pop at t2 > t1, whereas [LiveGate] treats a disintegrated
## vertex as dead and never pops it. The live behaviour is the correct one;
## the batch pass survives only as the up-front AI/preview estimate.
##
## #498 step 3 is what retires the duplication: once `resolve_against(slice)`
## exists, the estimate runs THIS gate against a shadow slice and
## [method resolve] is deleted outright. Do not "fix" the divergence by
## folding one into the other before then — that would silently change the
## AI's shape-risk signal ([member AttackOutcome.thinned_nodes]), which is a
## separate decision from #502's landing gate.
class LiveGate extends RefCounted:
	## Accepted pops so far, in the same shape [method resolve] returns —
	## [MeleePreview] replays this post-application (#502's "Watch": the
	## preview replays the applier's ACCEPTED set, never a fresh rescan).
	var result := Result.new()
	var _state: BladeState
	var _attacker: Entity

	func _init(state: BladeState, attacker: Entity) -> void:
		_state = state
		_attacker = attacker

	## True if `ev`'s damage should actually land right now. Call exactly
	## once per event, in true time order — mutates `result` when a contact
	## turns out to be a live pop.
	##
	## [param world] selects which world the allocation / ownership / spike
	## reads come from (#498 step 3); null means the live one, so a caller
	## outside the applier reads exactly what it used to.
	func admit(ev: BladeHitEvent, world: CombatWorld = null) -> bool:
		var w: CombatWorld = world if world != null else CombatWorld.live()
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
		var power := node.get_spike_power()
		if power <= 0.0:
			return true
		_kill(ev.particle_idx, ev.t, real_node, power, w)
		return false  # the popping contact itself deals no damage

	func _kill(particle_idx: int, t: float, defender: SkillNode, power: float,
			world: CombatWorld) -> void:
		result.dead_at[particle_idx] = t
		var pop := Pop.new(particle_idx, t, defender, power)
		result.pops.append(pop)
		# #504: a spike pop is a MODEL event, announced where it happens. This
		# runs inside `admit` inside `land_on` inside the applier's beat, so the
		# cue fires on the mutation clock — the same clock the damage, the
		# health bar and the shatter are on.
		#
		# It used to be re-announced by [MeleePreview] during the animation
		# replay, which only worked because the whole outcome was applied
		# BEFORE the replay started and `result.pops` was therefore complete.
		# Under design B the swing animates concurrently with the mutation, so
		# that snapshot would be empty; racing two timers at the same `t` is
		# the disease, not the fix.
		#
		# Safe to emit from here: `_kill` is [LiveGate]'s alone. The pure
		# estimate path ([method BladePopResolver.resolve], which
		# `ai_blade_rollout` runs on [WorkerThreadPool]) has its own inline
		# logic and never reaches this — so a rollout still cannot touch the bus.
		#
		# The shadow guard is the SAME branch [NodeCombat] has as `host != null`,
		# one layer out: a pop cue is a notification, and a resolve against a
		# shadow world must make none. Note this is not a preview flag — nothing
		# below it computes differently, the announcement simply has no audience.
		if not world.is_shadow():
			Events.blade_vertex_popped.emit(pop.defender, _attacker, pop.position)
		var removed: Dictionary = {}
		for k in result.dead_at:
			removed[k] = true
		var reachable := BladePopResolver._reachable_from_pivot(_state, removed)
		for v in _state.positions.size():
			if v == _state.pivot_index or removed.has(v):
				continue
			if not reachable.has(v):
				result.dead_at[v] = minf(result.dead_at.get(v, INF), t)


## BFS from the pivot over `state.edges`, skipping any vertex in `removed`.
## Returns a set (Dictionary) of reachable particle indices.
static func _reachable_from_pivot(state: BladeState, removed: Dictionary) -> Dictionary:
	var reach: Dictionary = {}
	var pivot := state.pivot_index
	reach[pivot] = true
	var queue: Array[int] = [pivot]
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		for e in state.edges:
			var other := -1
			if e.x == cur:
				other = e.y
			elif e.y == cur:
				other = e.x
			if other < 0 or removed.has(other) or reach.has(other):
				continue
			reach[other] = true
			queue.append(other)
	return reach
