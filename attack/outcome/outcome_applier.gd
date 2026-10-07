class_name OutcomeApplier

## The one place an [AttackOutcome] is applied to the world — the double-
## dispatch counterpart to [method HitInstance.land_on] (#381). A static
## utility rather than a Node/system: [method BattleSystem._apply_outcome]
## is its only caller today (#474 made VFX a pure observer, so the
## original two-caller design this issue started from no longer applies —
## see the plan/issue history), but it's named and isolated deliberately as
## the deterministic "apply this outcome" boundary #458's command-replay
## model will want.


## Land every hit in SCHEDULE order, not append order
## (docs/domain/attack-timeline.md "Ordering and arrival_time") — this
## is the half that actually fixes allocation order leaking into combat
## outcome; the per-mode ramps (ranged's rank-authored schedule, magic's
## propagation beat, melee's `BladeHitEvent.t`) are what make the order
## meaningful.
##
## [b]Order is the schedule's structure; the WAIT is its seconds[/b] (#543).
## Those are two different jobs that [member HitInstance.arrival_time] used to
## do at once, and separating them is what lets tempo be per-peer: the sort
## below keys off [member HitInstance.schedule_index], which every machine
## derives identically from the same structure, while the wait reads seconds no
## two machines need to agree on. Compiling here when the outcome has no
## schedule yet is deliberate — a replayed record arrives with structure and no
## seconds, and there must be exactly one place that turns one into the other.
##
## Design B (#504): this loop is also the [b]clock[/b]. It waits out each hit's
## `arrival_time` on [param clock] before landing it, so the world mutates when
## the arrow arrives rather than at t=0 with the picture catching up later.
## Everything that draws is then reading the model, on one clock, by
## construction — there is no view store to keep in step. Pass
## [method BeatClock.instant_clock] (the default) to land the whole outcome
## synchronously; see [BeatClock] for why this is not frame-ordered mutation.
##
## [param alloc] is read only by a [GateFlipInstance] landing on a LIVE world
## (#1209) — a melee fuse's real flip goes through
## [method AllocationSystem.apply_gate_flip_recorded]. Null skips such a
## landing with a warning rather than flipping without the cascade.
##
## [param world] chooses WHICH world it lands in (#535). Hand it
## [method CombatWorld.live] for a real launch or a peer replay, or a
## [method CombatWorld.shadow] and the identical loop, the identical gates and
## the identical arithmetic run against detached slices instead — which is what
## makes "the preview is the execution path" a fact rather than a discipline.
## There is deliberately no `is_preview` flag anywhere below: the only thing that
## differs is which [NodeCombat] the lookup returns.
##
## [b]Required, and deliberately placed ahead of the optional [param clock].[/b]
## Owner call 2026-08-23, on the project's own no-parallel-mirrors rule: a
## defaulted `world = null` would put an implicit live branch back inside this
## function, which is exactly the shape #498 exists to delete. #498's goal is
## that "the sim and the real path agree" holds by construction; a nullable world
## makes it hold by discipline again. Naming the world at the call site costs
## eleven lines repo-wide and buys back the guarantee.
static func apply(outcome: AttackOutcome, world: CombatWorld,
		clock: BeatClock = null, alloc: AllocationSystem = null) -> void:
	var beat: BeatClock = clock if clock != null else BeatClock.instant_clock()
	if outcome.schedule == null:
		outcome.schedule = OutcomeSchedule.compile(outcome)
	# One `schedule_index` group is one beat for the removal collector: every
	# node stripped by the group's landings spills over their union, flushed
	# before the next group lands (CombatWorld.flush_removals).
	var group := -1
	for hit in in_arrival_order(outcome.hits):
		if hit.target == null:
			continue
		if hit.schedule_index != group:
			world.flush_removals()
			group = hit.schedule_index
		# `advance_to` is declared `-> void`, so the analyzer calls this await
		# redundant — it is a runtime coroutine (it parks on a timer) and
		# dropping the await would land the whole volley on frame one.
		@warning_ignore("redundant_await")
		await beat.advance_to(hit.arrival_time)
		land_one(hit, world, alloc, outcome.crit_stream)
	world.flush_removals()


## One landing, gate and cue included — the body of [method apply]'s loop, and
## the only place a [method HitInstance.land_on] is reached from.
##
## Extracted (#536) because magic cannot wait for that loop: its candidate
## filter reads ownership, so wave N's kill has to be IN the world before wave
## N+1's filter runs, and [method SpellResolver.resolve_against] therefore lands
## each wave mid-walk. Calling this rather than re-deriving the same four lines
## there is what keeps "the sim and the real path agree" a structural fact —
## there is one landing implementation, and the world it lands in is an
## argument.
##
## Never [code]await[/code]s, deliberately: the clock is [method apply]'s
## concern, so a mid-walk caller pays no coroutine and cannot accidentally
## stagger a wave it meant to land at once.
##
## [b]The crit is a landing fact.[/b] Given [param crit_rng] — a fresh
## resolve's [member AttackOutcome.crit_stream] — the hit draws its crit
## ([method CritRoll.decide]) right before it lands, reading [param world] as
## the landings before it left it, so a status landed earlier in the same
## attack reaches its chance. Null on a replay (a rebuilt record carries no
## stream): the recorded crit lands as-is. Never key that off a per-hit field
## — a recorded hit with no dealloc would read as fresh and re-draw. A hit
## that does not reach its landing (freed target or origin) draws nothing.
static func land_one(hit: HitInstance, world: CombatWorld,
		alloc: AllocationSystem = null, crit_rng: RandomNumberGenerator = null) -> void:
	if hit == null or hit.target == null:
		return
	# A rebuilt record arrives with its deallocations pre-populated (the
	# record's contract, see DeallocEntry); a fresh resolve never does. So
	# this is the replay signal: a record feeds the beat its recorded spill, a
	# fresh landing has the spill the flush computes written onto the entries
	# it just produced.
	var recorded := not hit.deallocations.is_empty()
	if recorded:
		world.feed_recorded(hit.deallocations)
	# A fuse's gate flip (#1209) lands on the TOPOLOGY, not on a slice — and
	# live it needs [param alloc], the one flip-and-cascade implementation.
	if hit.kind == HitInstance.Kind.GATE_FLIP:
		(hit as GateFlipInstance).land_flip(world, alloc)
		if not recorded:
			world.track_entries(hit.deallocations)
		return
	# Re-checked here rather than hoisted: an earlier beat's cascade can
	# free a target between landings. `origin` is checked too (#503) — a
	# mid-volley cascade can just as easily free the FIRING node (e.g. a
	# ranged leaf islanded by this same volley's overkill), and a mode
	# whose live offense read needs `origin` (RangedHitInstance) must not
	# be handed a freed one. This is instance-validity only, the coarse
	# net; the meaningful allocated/hostile gate is each mode's own
	# `land_on` (see RangedHitInstance, BladeDamageInstance for #502).
	if not is_instance_valid(hit.target):
		return
	if hit.origin != null and not is_instance_valid(hit.origin):
		return
	# The identity -> state translation, in the one place that performs it.
	# `hit.target` stays the real node throughout; what varies is the slice it
	# resolves to.
	var slice := world.combat_for(hit.target)
	if slice == null:
		return
	if crit_rng != null:
		CritRoll.decide(hit, crit_rng, world)
	hit.land_on(slice, world)
	if not recorded:
		world.track_entries(hit.deallocations)
	# The one recorded PRESENTATION cue (#536), announced on the mutation clock
	# because this is the mutation clock. Guarded exactly like [NodeCombat]'s
	# `host != null` branch: a shadow world has no audience, so the authority's
	# compute pass stays silent and the cue fires on the live replay — see
	# [member HitInstance.popped_vertex].
	if hit.popped_vertex != null and not world.is_shadow():
		Events.blade_vertex_popped.emit(
				hit.popped_vertex, hit.attacker, hit.popped_vertex.global_position)


## Decorate-sort-undecorate on `(schedule_index, original_index)`. This is
## also the order the crit stream is consumed in — [method land_one] draws as
## each hit lands — so a replayed seed reproduces the same crits only while
## this order is the one every peer agrees on.
##
## [b]The key is the structural entry index, never seconds[/b] (#543 D2, and
## the one decision on that issue whose violation produces a green suite and a
## desync). Land order is gameplay-observable — node-local armour reads at land
## time, forced-dealloc cascades run synchronously between landings, and
## [CritRoll] draws in exactly this sequence — while seconds became
## tempo-dependent the moment tempo became a per-peer setting. Two peers at
## different [member GameSettings.combat_time_scale] therefore hold different
## floats for the same landing and the SAME [member HitInstance.schedule_index],
## which is the only reason D4's "recompile per peer" is safe.
## [b]Never reintroduce a sort or compare on [member HitInstance.arrival_time].[/b]
##
## [method Array.sort_custom] is not documented stable in Godot 4.x, and
## all three modes still produce genuine ties (a whole magic wave shares one
## beat and therefore one entry; a melee sim substep can land two events at the
## same normalized `t`) — an unstable sort would permute their application
## order nondeterministically. Sorting on the original index as a tiebreak
## makes this a provable no-op for any outcome whose hits all tie, exactly as
## it did when the primary key was a float.
##
## [member SkillNode.stable_id] is NOT the tiebreak here — it's the ranged
## ramp's OWN rank tiebreak (see [method RangedAttackPlan.get_firing_schedule]).
## Applied globally it would reorder magic hits out of wave order.
static func in_arrival_order(hits: Array[HitInstance]) -> Array[HitInstance]:
	var decorated: Array = []
	for i in hits.size():
		decorated.append([hits[i].schedule_index, i, hits[i]])
	decorated.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	var ordered: Array[HitInstance] = []
	for entry in decorated:
		ordered.append(entry[2])
	return ordered
