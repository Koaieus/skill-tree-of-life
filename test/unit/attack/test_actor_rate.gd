extends GutTest

## #819 — a non-local actor's melee swing plays at a faster presentation rate.
## [method OutcomeSchedule.actor_rate] is the one composer; this file exercises
## its seat predicate and the resulting schedule shape, never the chosen
## multiplier — the owner's to retune (#819 decision 5), so every assertion
## here is directional (`assert_lt`/`assert_eq`), not a pinned number.
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

func test_a_non_seated_actors_schedule_is_strictly_shorter_than_a_seated_ones() -> void:
	var policy := SeatPolicy.seat(1)
	var mine := _entity(1, true)
	var theirs := _entity(2, false)

	var seated_rate := OutcomeSchedule.actor_rate(policy, mine)
	var non_seated_rate := OutcomeSchedule.actor_rate(policy, theirs)

	var seated := OutcomeSchedule.compile(_beat_outcome(), _beat_tempo(), seated_rate)
	var non_seated := OutcomeSchedule.compile(_beat_outcome(), _beat_tempo(), non_seated_rate)

	assert_lt(non_seated.duration(), seated.duration(),
			"a non-seated actor's swing must occupy less wall-clock time, " +
			"at the same combat_time_scale")


func test_the_gap_holds_at_a_non_default_combat_time_scale_too() -> void:
	# `combat_time_scale` is read ambiently by `ambient_rate()`; this file has
	# no live Settings autoload, so both sides fold in the same 1.0 ambient
	# rate here regardless — the assertion still has to hold, since the seat
	# factor composes multiplicatively with whatever the ambient rate is.
	var policy := SeatPolicy.seat(1)
	var mine := _entity(1, true)
	var theirs := _entity(2, false)
	var seated := OutcomeSchedule.compile(_beat_outcome(), _beat_tempo(),
			OutcomeSchedule.actor_rate(policy, mine, 2.0))
	var non_seated := OutcomeSchedule.compile(_beat_outcome(), _beat_tempo(),
			OutcomeSchedule.actor_rate(policy, theirs, 2.0))
	assert_lt(non_seated.duration(), seated.duration())


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


func test_a_couch_still_speeds_up_an_npc() -> void:
	var policy := SeatPolicy.couch()
	var npc := _entity(3, false)
	assert_lt(OutcomeSchedule.actor_rate(policy, npc), OutcomeSchedule.ambient_rate(),
			"an AI is nobody's seat even on a couch")


# -- Decision 4: the predicate is SeatPolicy.seats(actor), null is unseated --

func test_a_null_seat_policy_is_treated_as_unseated() -> void:
	var npc := _entity(3, false)
	assert_lt(OutcomeSchedule.actor_rate(null, npc), OutcomeSchedule.ambient_rate(),
			"an unwired BattleSystem must not silently default to the seated pace")


func test_an_unresolved_actor_is_treated_as_unseated() -> void:
	var policy := SeatPolicy.seat(1)
	assert_lt(OutcomeSchedule.actor_rate(policy, null), OutcomeSchedule.ambient_rate(),
			"an actor that fails to resolve is unseated, exactly as " +
			"CommandApplier._pre_roll and CameraDirector._build_attack_request treat it")


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

## Same shape as `test_melee_playback_follows_schedule.gd`'s contract tests,
## but driven off `OutcomeSchedule.actor_rate`'s non-seated branch specifically
## — the door #819 opens, not an arbitrary rate.
func test_the_blade_stays_locked_to_the_schedule_at_a_non_seated_actor_rate() -> void:
	var policy := SeatPolicy.seat(1)
	var npc := _entity(9, false)
	var rate := OutcomeSchedule.actor_rate(policy, npc)
	assert_lt(rate, 1.0, "precondition: a non-seated actor really does compose to a faster rate")

	var schedule := OutcomeSchedule.compile(_swing_outcome(), _swing_tempo(), rate)
	var sim_duration := 1.2
	var playback_rate := schedule.blade_playback_rate(sim_duration)
	var wall := sim_duration / playback_rate

	assert_almost_eq(wall, schedule.duration(), 0.0001,
			"the blade's derived draw time must match the schedule's own span " +
			"even at the non-seated rate")
	for i in schedule.entries.size():
		var drawn_at: float = schedule.entries[i].structural_key * sim_duration / playback_rate
		assert_almost_eq(drawn_at, schedule.entries[i].arrive_at, 0.0001,
				"contact %d must still land at the moment the blade draws it" % i)
