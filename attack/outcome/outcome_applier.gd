class_name OutcomeApplier

## The one place an [AttackOutcome] is applied to the world — the double-
## dispatch counterpart to [method HitInstance.land_on] (#381). A static
## utility rather than a Node/system: [method BattleSystem._apply_outcome]
## is its only caller today (#474 made VFX a pure observer, so the
## original two-caller design this issue started from no longer applies —
## see the plan/issue history), but it's named and isolated deliberately as
## the deterministic "apply this outcome" boundary #458's command-replay
## model will want.


## Land every hit in [member HitInstance.arrival_time] order, not append
## order (docs/domain/attack-timeline.md "Ordering and arrival_time") — this
## is the half that actually fixes allocation order leaking into combat
## outcome; the per-mode ramps (ranged's rank-authored schedule, magic's
## propagation beat, melee's `BladeHitEvent.t`) are what make the order
## meaningful.
##
## Design B (#504): this loop is also the [b]clock[/b]. It waits out each hit's
## `arrival_time` on [param clock] before landing it, so the world mutates when
## the arrow arrives rather than at t=0 with the picture catching up later.
## Everything that draws is then reading the model, on one clock, by
## construction — there is no view store to keep in step. Pass
## [method BeatClock.instant_clock] (the default) to land the whole outcome
## synchronously; see [BeatClock] for why this is not frame-ordered mutation.
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
		clock: BeatClock = null) -> void:
	var beat: BeatClock = clock if clock != null else BeatClock.instant_clock()
	for hit in in_arrival_order(outcome.hits):
		if hit.target == null:
			continue
		# `advance_to` is declared `-> void`, so the analyzer calls this await
		# redundant — it is a runtime coroutine (it parks on a timer) and
		# dropping the await would land the whole volley on frame one.
		@warning_ignore("redundant_await")
		await beat.advance_to(hit.arrival_time)
		# Re-checked here rather than hoisted: an earlier beat's cascade can
		# free a target between landings. `origin` is checked too (#503) — a
		# mid-volley cascade can just as easily free the FIRING node (e.g. a
		# ranged leaf islanded by this same volley's overkill), and a mode
		# whose live offense read needs `origin` (RangedHitInstance) must not
		# be handed a freed one. This is instance-validity only, the coarse
		# net; the meaningful allocated/hostile gate is each mode's own
		# `land_on` (see RangedHitInstance, BladeDamageInstance for #502).
		if is_instance_valid(hit.target) and (hit.origin == null or is_instance_valid(hit.origin)):
			# The identity -> state translation, in the one place that performs
			# it. `hit.target` stays the real node throughout; what varies is the
			# slice it resolves to.
			var slice := world.combat_for(hit.target)
			if slice != null:
				hit.land_on(slice, world)


## Decorate-sort-undecorate on `(arrival_time, original_index)`. Public
## because [method CritRoll.decide_all] must consume its seeded stream in the
## exact order this lands hits (#507) — a second sort written to match would
## be free to drift out of step with this one, and the symptom would be crits
## that stop reproducing under a replayed seed.
## [method Array.sort_custom] is not documented stable in Godot 4.x, and
## all three modes still produce genuine ties (magic stamps a whole wave at
## one `hop_index * WAVE_ARRIVAL_INTERVAL`; a melee sim substep can land two
## events at the same `t`) — an unstable sort would permute their application
## order nondeterministically, which is gameplay-observable here (node-local
## armour + synchronous force-dealloc cascades both read at land time).
## Sorting on the original index as a tiebreak makes this a provable no-op for
## any outcome whose hits all tie.
##
## [member SkillNode.stable_id] is NOT the tiebreak here — it's the ranged
## ramp's OWN rank tiebreak (see [method RangedAttackPlan.get_firing_schedule]).
## Applied globally it would reorder magic hits out of wave order.
static func in_arrival_order(hits: Array[HitInstance]) -> Array[HitInstance]:
	var decorated: Array = []
	for i in hits.size():
		decorated.append([hits[i].arrival_time, i, hits[i]])
	# Exact float comparison, deliberately — NOT is_equal_approx. An
	# approximate tie test is not transitive (a~b and b~c does not give a~c
	# for times spaced just under the epsilon), which violates the strict
	# weak ordering sort_custom requires and can misorder or read out of
	# bounds. Every intended tie here is exact anyway: a magic wave stamps one
	# `hop_index * WAVE_ARRIVAL_INTERVAL` across the whole wave, and two shots
	# at the same rank produce the same lerp output bit-for-bit.
	decorated.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	var ordered: Array[HitInstance] = []
	for entry in decorated:
		ordered.append(entry[2])
	return ordered
