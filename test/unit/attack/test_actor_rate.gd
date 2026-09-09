extends GutTest

## #819 — [method OutcomeSchedule.actor_rate], the one composer of a melee
## replay's presentation rate. This file exercises the DOOR: that ambient rate,
## seat factor and sandbox scale compose, that the #818 blade contract survives
## a non-1.0 rate, and that no rate ever reorders a hit.
##
## [b]It no longer asserts that a non-seated actor is faster.[/b] #819 shipped
## that on 2026-09-10 and the owner overruled it the same night — a swing you
## did not choose is the one you most need to READ, so the seat is the wrong
## axis (see [constant OutcomeSchedule._NON_SEATED_RATE_FACTOR], held at 1.0).
## The successor predicate is relevance — vision + ownership — and it brings its
## own directional tests. What survives here is everything that was never about
## the seat.
##
## No assertion pins the chosen multiplier; those are the owner's to retune.
##
## The convention trap (#819's own unit-clarification comment): the compiled
## `rate` MULTIPLIES duration, so "faster" is a SMALLER rate and a SHORTER
## `duration()` — the one thing this file asserts on, never a raw multiplier.

const _SWING := 0.3


func _entity(id: int, human: bool) -> Entity:
	var e := Entity.new()
	e.entity_id = id
	e.is_human_controlled = human
	autofree(e)
	return e


func _beat_tempo() -> PresentationTempo:
	var tempo := PresentationTempo.new()
	tempo.beat_interval = 0.4
	tempo.beat_lead_in = 0.1
	return tempo


func _swing_tempo() -> PresentationTempo:
	var tempo := PresentationTempo.new()
	tempo.swing_duration = _SWING
	return tempo


func _beat_outcome() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.BEAT
	for key in [0.0, 1.0, 2.0]:
		var hit := DamageInstance.new()
		hit.amount = 10.0
		hit.effective_amount = 10.0
		hit.structural_key = key
		outcome.hits.append(hit)
		var ev := PropagationEvent.new()
		ev.beat = int(key)
		ev.hits.append(hit)
		outcome.timeline.append(ev)
	return outcome


## A SWING-cadence outcome keyed the way melee production keys one —
## structural_key is a fraction of the swing, exactly [method
## test_melee_playback_follows_schedule._swing_outcome]'s shape.
func _swing_outcome() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.SWING
	for t in [0.0, 0.25, 0.5, 1.0]:
		var hit := DamageInstance.new()
		hit.amount = 10.0
		hit.effective_amount = 10.0
		hit.structural_key = t
		outcome.hits.append(hit)
	return outcome


# -- Acceptance 1: a non-seated actor's schedule is strictly shorter ----------

## Owner call 2026-09-10, verbatim: [i]"why would we want to speed up swings for
## non-local actors? [...] you need to see it form before it swings at you and
## kills you dead"[/i]. So an incoming swing plays at YOUR pacing, and this
## asserts the parity rather than the gap #819 originally shipped.
func test_an_incoming_swing_plays_at_the_same_pace_as_your_own() -> void:
	var policy := SeatPolicy.seat(1)
	var mine := _entity(1, true)
	var theirs := _entity(2, false)

	var seated := OutcomeSchedule.compile(_beat_outcome(), _beat_tempo(),
			OutcomeSchedule.actor_rate(policy, mine))
	var non_seated := OutcomeSchedule.compile(_beat_outcome(), _beat_tempo(),
			OutcomeSchedule.actor_rate(policy, theirs))

	assert_almost_eq(non_seated.duration(), seated.duration(), 0.0001,
			"a swing you did not choose is the one you most need to read — " +
			"the seat must not shorten it")


## The sandbox scale (#820) is a real, composing input to the same door, and
## unlike the seat factor it is SUPPOSED to change the span. Guards the
## composition itself, so holding the seat factor at 1.0 cannot quietly make
## `actor_rate` a constant function nobody would notice was broken.
func test_the_sandbox_scale_still_stretches_the_span() -> void:
	var policy := SeatPolicy.seat(1)
	var mine := _entity(1, true)
	var normal := OutcomeSchedule.compile(_beat_outcome(), _beat_tempo(),
			OutcomeSchedule.actor_rate(policy, mine, 1.0))
	var slowed := OutcomeSchedule.compile(_beat_outcome(), _beat_tempo(),
			OutcomeSchedule.actor_rate(policy, mine, 2.0))
	assert_lt(normal.duration(), slowed.duration(),
			"scale MULTIPLIES duration, so 2.0 is slow motion")


# -- Acceptance 4: a seated actor's pacing is unchanged from today -----------

func test_a_seated_actors_rate_is_exactly_the_ambient_rate() -> void:
	var policy := SeatPolicy.seat(1)
	var mine := _entity(1, true)
	assert_almost_eq(OutcomeSchedule.actor_rate(policy, mine), OutcomeSchedule.ambient_rate(),
			0.0001, "a seated actor's rate must be untouched by #819")


func test_a_couch_seats_every_human_so_every_human_keeps_todays_pace() -> void:
	var policy := SeatPolicy.couch()
	var hero := _entity(1, true)
	var partner := _entity(2, true)
	assert_almost_eq(OutcomeSchedule.actor_rate(policy, hero), OutcomeSchedule.ambient_rate(), 0.0001)
	assert_almost_eq(OutcomeSchedule.actor_rate(policy, partner), OutcomeSchedule.ambient_rate(),
			0.0001, "couch seats every human, so a hot-seat partner's pace is unchanged too")


func test_an_npc_on_a_couch_keeps_todays_pace_too() -> void:
	var policy := SeatPolicy.couch()
	var npc := _entity(3, false)
	assert_almost_eq(OutcomeSchedule.actor_rate(policy, npc), OutcomeSchedule.ambient_rate(),
			0.0001, "an AI swinging at you is exactly the case that must stay readable")


# -- An unwired or unresolvable actor must still produce a SANE rate ---------

func test_a_null_seat_policy_still_composes_a_usable_rate() -> void:
	var npc := _entity(3, false)
	assert_almost_eq(OutcomeSchedule.actor_rate(null, npc), OutcomeSchedule.ambient_rate(),
			0.0001, "an unwired BattleSystem must not invent a pace of its own")


func test_an_unresolved_actor_still_composes_a_usable_rate() -> void:
	var policy := SeatPolicy.seat(1)
	assert_almost_eq(OutcomeSchedule.actor_rate(policy, null), OutcomeSchedule.ambient_rate(),
			0.0001, "an actor that fails to resolve must not hang the presentation")


# -- Acceptance 3: the rate scales the span, never a hit's order or identity --

func test_the_rate_never_reorders_or_retargets_a_hit() -> void:
	var seated_outcome := _beat_outcome()
	var fast_outcome := _beat_outcome()
	OutcomeSchedule.compile(seated_outcome, _beat_tempo(), 1.0)
	OutcomeSchedule.compile(fast_outcome, _beat_tempo(), 0.5)
	for i in seated_outcome.hits.size():
		assert_eq(seated_outcome.hits[i].schedule_index, fast_outcome.hits[i].schedule_index,
				"a landing's structural index must not move with the rate")


# -- Acceptance 2: the #818 blade contract holds at a non-1.0 actor rate -----

## Same shape as `test_melee_playback_follows_schedule.gd`'s contract tests, but
## driven through `OutcomeSchedule.actor_rate` — the door — rather than an
## arbitrary rate. Uses the sandbox scale to reach a non-1.0 rate, since the
## seat factor no longer produces one.
func test_the_blade_stays_locked_to_the_schedule_at_a_non_default_actor_rate() -> void:
	var policy := SeatPolicy.seat(1)
	var npc := _entity(9, false)
	var rate := OutcomeSchedule.actor_rate(policy, npc, 0.5)
	assert_lt(rate, 1.0, "precondition: the door really does compose to a non-1.0 rate")

	var schedule := OutcomeSchedule.compile(_swing_outcome(), _swing_tempo(), rate)
	var sim_duration := 1.2
	var playback_rate := schedule.blade_playback_rate(sim_duration)
	var wall := sim_duration / playback_rate

	assert_almost_eq(wall, schedule.duration(), 0.0001,
			"the blade's derived draw time must match the schedule's own span " +
			"even at a non-default rate")
	for i in schedule.entries.size():
		var drawn_at: float = schedule.entries[i].structural_key * sim_duration / playback_rate
		assert_almost_eq(drawn_at, schedule.entries[i].arrive_at, 0.0001,
				"contact %d must still land at the moment the blade draws it" % i)
