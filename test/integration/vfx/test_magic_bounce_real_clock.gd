extends GutTest

## The one real-clock test for [MagicBounceCoordinator]: `clock` left null, so
## each cast walks its own [method BeatClock.for_tree]. The unit tier drives the
## wave cadence on an instant clock (test/unit/vfx/test_magic_bounce_coordinator.gd);
## what only the real clock can show is that `await play()` resolves after the
## WHOLE timeline. AttackVFX frees the coordinator the moment it does, so an
## early return silently drops every later beat.
##
## Driven by the deterministic trigger rather than a timing race: a first beat
## that spawns NOTHING. `_play_cancel` returns before touching the pending
## counter when `cancel_visual` is null, so the drain would fall straight
## through if `play()` did not await the timeline first — at any tuning.

var _helper: SpellTestHelper
var _graph: Graph


func before_each() -> void:
	_helper = SpellTestHelper.new()
	_graph = _helper.make_graph([[0, 1], [1, 2]], self)


func test_play_does_not_return_before_the_last_beat() -> void:
	var nodes := _graph.get_skill_nodes()
	var coord := MagicBounceCoordinator.new()
	var tempo := PresentationTempo.new()
	tempo.beat_interval = 0.05
	tempo.beat_lead_in = 0.03
	coord.tempo = tempo
	coord.cancel_visual = null  # beat 0 will spawn nothing at all
	add_child_autofree(coord)

	var outcome := AttackOutcome.new()
	var cancel_ev := PropagationEvent.new()
	cancel_ev.beat = 0
	cancel_ev.verb = PropagationEvent.Verb.CANCEL
	cancel_ev.origin = nodes[0]
	cancel_ev.target = nodes[1]
	outcome.timeline.append(cancel_ev)
	var hit_ev := PropagationEvent.new()
	hit_ev.beat = 1
	hit_ev.verb = PropagationEvent.Verb.EDGE
	hit_ev.origin = nodes[1]
	hit_ev.target = nodes[2]
	var hit := DamageInstance.new()
	hit.origin = nodes[1]
	hit.target = nodes[2]
	hit.amount = 1.0
	hit_ev.hits.append(hit)
	outcome.hits.append(hit)
	outcome.timeline.append(hit_ev)

	var events: Array = []
	coord.wave_started.connect(func(hop: int, _c: int) -> void:
		events.append(hop))
	var state := {"done": false, "events_at_return": []}
	var run := func() -> void:
		await coord.play(outcome)
		state.events_at_return = events.duplicate()
		state.done = true
	run.call()

	await wait_until(func() -> bool: return state.done, 15.0)
	assert_true(state.done, "play() never returned within 15 s")
	assert_eq(state.events_at_return, [0, 1],
		"play() resolved after only %d of 2 beats — AttackVFX frees the " % (state.events_at_return as Array).size()
			+ "coordinator here, so the rest of the timeline is dropped")
