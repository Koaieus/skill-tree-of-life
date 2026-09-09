extends GutTest

## #818 — the melee blade must draw on the same rate-scaled clock its hits land
## on. Before this, `OutcomeSchedule` multiplied every melee arrival by the
## player's `combat_time_scale` while `SkillBlade.play` always took its 1.0
## `playback_rate` default (no production caller anywhere), so at 2.0x the arc
## finished a full second before the last damage number appeared.
##
## The two knobs point OPPOSITE ways — the compiler multiplies duration
## (`arrive_at *= rate`), `play` divides it (`dur / playback_rate`) — which is
## why the fix is a derived ratio and not a copy of `rate`. These tests pin the
## ratio, not the transcription.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

## Deliberately NOT 1.2: a tempo whose swing_duration happened to equal
## [constant MeleeAttackPlan.SWING_DURATION] would make the correct answer and
## the buggy one (playback_rate 1.0) agree at rate 1.0, hiding half of what
## this file checks.
const _SWING := 0.3

const _SIM_DT := 0.05
## A production-shaped trajectory: SWING_DURATION long, so the blade times
## these tests measure are the ones a real swing produces.
const _SIM_STEPS := 24

## The blade times the fixture's contacts happen at, in SIM seconds.
const _CONTACT_TIMES: Array[float] = [0.0, 0.3, 0.9, 1.2]


func _tempo() -> PresentationTempo:
	var tempo := PresentationTempo.new()
	tempo.swing_duration = _SWING
	return tempo


## Every sample is the same pose — motion is irrelevant to timing.
func _traj() -> BladeTrajectory:
	var traj := BladeTrajectory.new()
	traj.sample_dt = _SIM_DT
	traj.samples = []
	for _k in range(_SIM_STEPS + 1):
		traj.samples.append(PackedVector2Array([Vector2.ZERO, Vector2(80.0, 0.0)]))
	return traj


## A SWING-cadence outcome keyed exactly the way production keys one —
## `structural_key = blade time / SWING_DURATION` (`melee_attack_plan.gd:945`).
func _swing_outcome() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.SWING
	for t in _CONTACT_TIMES:
		var hit := DamageInstance.new()
		hit.amount = 10.0
		hit.effective_amount = 10.0
		hit.structural_key = t / MeleeAttackPlan.SWING_DURATION
		outcome.hits.append(hit)
	return outcome


func _schedule(rate: float) -> OutcomeSchedule:
	return OutcomeSchedule.compile(_swing_outcome(), _tempo(), rate)


func _rate_for(schedule: OutcomeSchedule) -> float:
	return schedule.blade_playback_rate(MeleeAttackPlan.SWING_DURATION)


# -- the arithmetic -----------------------------------------------------------

## The load-bearing invariant, per contact rather than per arc: the wall-clock
## moment the blade reaches a node is the moment that node takes its hit.
##
## `SkillBlade.play` tweens the VALUE range [0, dur] over `dur / playback_rate`
## wall seconds, so a contact at blade time `t` is drawn at wall `t / rate`.
func test_every_contact_is_drawn_at_the_moment_it_lands() -> void:
	for rate in [0.5, 1.0, 2.0, 3.0]:
		var schedule := _schedule(rate)
		var pb := _rate_for(schedule)
		for i in _CONTACT_TIMES.size():
			var drawn_at: float = _CONTACT_TIMES[i] / pb
			var lands_at: float = schedule.entries[i].arrive_at
			assert_almost_eq(drawn_at, lands_at, 0.0001,
					"rate %s, contact %s: blade arrives at %ss, hit lands at %ss" \
							% [rate, i, drawn_at, lands_at])


## The whole arc, as a cross-check on the per-contact assertion above: the
## blade's total wall time is the schedule's span, since the last contact sits
## at the end of the swing.
func test_blade_wall_duration_matches_the_schedule_span() -> void:
	for rate in [0.5, 1.0, 2.0]:
		var schedule := _schedule(rate)
		var wall: float = MeleeAttackPlan.SWING_DURATION / _rate_for(schedule)
		assert_almost_eq(wall, schedule.duration(), 0.0001,
				"rate %s: blade draws for %ss, hits land over %ss" \
						% [rate, wall, schedule.duration()])


## The bug in one assertion: the rate is inversely proportional to the clock's,
## which is exactly what the 1.0 default could never be.
func test_the_derived_rate_inverts_the_clock_rate() -> void:
	var base := _rate_for(_schedule(1.0))
	assert_almost_eq(_rate_for(_schedule(2.0)), base * 0.5, 0.0001,
			"a 2x-slower clock wants a 2x-slower blade")
	assert_almost_eq(_rate_for(_schedule(0.5)), base * 2.0, 0.0001,
			"a 2x-faster clock wants a 2x-faster blade")


## Acceptance 2 — a fix, not a retune. With the shipped tempo (swing_duration
## == SWING_DURATION) at rate 1.0 the derivation is `x / x`, which IEEE makes
## exactly 1.0 — so `wall_duration = dur / 1.0` is bit-identical to the value
## the old hardcoded default produced. Asserted with `assert_eq`, not an
## epsilon, because "exactly today's pace" is the claim.
func test_default_tempo_at_rate_one_is_bit_identical_to_today() -> void:
	var schedule := OutcomeSchedule.compile(_swing_outcome(), null, 1.0)
	assert_eq(schedule.tempo.swing_duration, MeleeAttackPlan.SWING_DURATION,
			"precondition: the shipped tempo still matches the sim constant")
	assert_eq(_rate_for(schedule), 1.0,
			"the shipped tempo at rate 1.0 must reproduce today's playback exactly")


## Degenerate inputs must not produce a zero or negative tween length, which
## Tween treats as "finish immediately" and would silently skip the swing.
func test_rate_stays_positive_on_degenerate_input() -> void:
	var floored := OutcomeSchedule.compile(_swing_outcome(), _tempo(), 0.0)
	assert_gt(_rate_for(floored), 0.0,
			"a zero rate must not yield a zero-length tween")
	assert_gt(_schedule(1.0).blade_playback_rate(0.0), 0.0,
			"a zero sim duration must not yield a zero-length tween")


# -- the wiring ---------------------------------------------------------------

## The arithmetic being right buys nothing if `MeleePreview.launch` still takes
## the default. Drives the real coroutine and times it — this is the assertion
## that was red before the fix.
func test_preview_launch_plays_on_the_schedules_clock() -> void:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var tip := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(tip)
	tip.position = Vector2(80.0, 0.0)
	graph.add_edge(pivot, tip)
	await get_tree().process_frame

	var preview := MeleePreview.new()
	add_child_autofree(preview)

	var plan := MeleeAttackPlan.new()
	plan.source = pivot
	plan.blade_nodes = [tip] as Array[SkillNode]
	plan.last_trajectory = _traj()
	plan.last_events = [] as Array[BladeHitEvent]

	# Godot's first Tween in a freshly-entered node runs on a skewed initial
	# delta (the same warm-up test_skill_blade_playback_rate.gd documents), so
	# burn one swing before timing anything.
	await preview.launch(plan, _schedule(1.0))

	var schedule := _schedule(2.0)
	var start := Time.get_ticks_msec()
	await preview.launch(plan, schedule)
	var elapsed: float = float(Time.get_ticks_msec() - start) / 1000.0
	# `launch` also runs a 0.45s fade after the swing; subtract it rather than
	# reaching into the coroutine.
	var swing_wall: float = elapsed - 0.45
	assert_almost_eq(swing_wall, schedule.duration(), 0.09,
			"the swing took %ss of wall clock; its hits land over %ss" \
					% [swing_wall, schedule.duration()])
