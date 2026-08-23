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

	func _init(state: BladeState, attacker: Entity) -> void:
		_state = state
		_attacker = attacker

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
		var power := node.get_spike_power()
		if power <= 0.0:
			return true
		_kill(ev.particle_idx, ev.t, real_node, power)
		return false  # the popping contact itself deals no damage

	func _kill(particle_idx: int, t: float, defender: SkillNode, power: float) -> void:
		result.dead_at[particle_idx] = t
		var pop := Pop.new(particle_idx, t, defender, power)
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
