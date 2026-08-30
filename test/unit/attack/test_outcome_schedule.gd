extends GutTest

## #543 — the schedule compiler. [b]The resolver emits structure; the compiler
## assigns seconds.[/b]
##
## The load-bearing one is D2: landing order keys off the structural entry
## index, never off seconds. A wrong sort key there produces a GREEN SUITE and
## a multiplayer desync — two peers at different
## [member GameSettings.combat_time_scale] hold different floats for the same
## landing — so this file asserts the invariant three ways: on the sort key
## itself, on [CritRoll]'s seeded stream, and by scanning the source for a
## reintroduced compare.

const _MODE_SOURCES: Array[String] = [
	"res://attack/spell/spell_resolver.gd",
	"res://attack/plan/ranged_attack_plan.gd",
	"res://attack/plan/melee_attack_plan.gd",
	"res://attack/plan/magic_attack_plan.gd",
]

var _h: SpellTestHelper


func before_each() -> void:
	_h = SpellTestHelper.new()


# -- fixtures -----------------------------------------------------------------

func _tempo(interval: float, lead: float) -> PresentationTempo:
	var tempo := PresentationTempo.new()
	tempo.beat_interval = interval
	tempo.beat_lead_in = lead
	return tempo


## A hand-built BEAT-cadence outcome — three landings on three hop ordinals,
## deliberately appended out of order so append order and structural order
## disagree and the sort has something to prove.
func _beat_outcome() -> AttackOutcome:
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.BEAT
	for key in [2.0, 0.0, 1.0]:
		var hit := DamageInstance.new()
		hit.amount = 10.0 * (key + 1.0)
		hit.effective_amount = hit.amount
		hit.structural_key = key
		outcome.hits.append(hit)
		var ev := PropagationEvent.new()
		ev.beat = int(key)
		ev.hits.append(hit)
		outcome.timeline.append(ev)
	return outcome


## A three-hop line cast through the real resolver, so every structural field
## is wired exactly the way production produces it.
func _resolved_line_cast(tempo: PresentationTempo = null, power: float = 100.0) -> Dictionary:
	var graph := _h.make_graph([[0, 1], [1, 2], [2, 3]], self)
	var nodes := graph.get_skill_nodes()
	var attacker := _h.make_entity(graph, "Attacker", Color.RED)
	var defender := _h.make_entity(graph, "Defender", Color.BLUE)
	_h.give_big_hp(defender)
	_h.assign_owner(graph, attacker, [0])
	_h.assign_owner(graph, defender, [1, 2, 3])
	var config := _h.make_config(_h.fan_all(), _h.owner_enemy(), null, {max_hops = 2})
	var spell := _h.make_spell(config, [DamageEffect.new()], power)
	spell.tempo = tempo
	return {
		"graph": graph,
		"outcome": SpellResolver.resolve(spell, nodes[1], nodes[0], attacker, graph),
	}


func _order(outcome: AttackOutcome) -> Array:
	var keys: Array = []
	for hit in OutcomeApplier.in_arrival_order(outcome.hits):
		keys.append(hit.schedule_index)
	return keys


func _amounts(outcome: AttackOutcome) -> Array:
	var out: Array = []
	for hit in OutcomeApplier.in_arrival_order(outcome.hits):
		out.append(hit.effective_amount)
	return out


# -- the compiler is pure -----------------------------------------------------

## Acceptance: "a pure compiler `(AttackOutcome, PresentationTempo) ->
## OutcomeSchedule` exists and is unit-tested WITHOUT instantiating any VFX
## node." Measured, not asserted by inspection — the node count is the thing
## that would move if a coordinator ever crept into the compile path.
func test_compiling_instantiates_no_node_at_all() -> void:
	var outcome := _beat_outcome()
	var before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var schedule := OutcomeSchedule.compile(outcome, _tempo(0.4, 0.35), 1.0)
	assert_eq(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), before,
			"the compiler must not instantiate a single Node")
	assert_eq(schedule.entries.size(), 3, "one entry per landing moment")


func test_the_rate_is_a_parameter_so_timing_is_never_ambient_in_a_test() -> void:
	var schedule := OutcomeSchedule.compile(_beat_outcome(), _tempo(0.4, 0.35), 1.0)
	assert_almost_eq(schedule.rate, 1.0, 0.0001)
	var slow := OutcomeSchedule.compile(_beat_outcome(), _tempo(0.4, 0.35), 3.0)
	assert_almost_eq(slow.rate, 3.0, 0.0001)


# -- D2: order is structure, seconds are presentation -------------------------

## The acceptance test for D2, stated exactly as the issue does: scaling tempo
## by 2x leaves the landing sequence byte-identical while every second doubles.
func test_doubling_the_tempo_doubles_every_second_and_moves_no_landing() -> void:
	var fast := _beat_outcome()
	var slow := _beat_outcome()
	var fast_schedule := OutcomeSchedule.compile(fast, _tempo(0.4, 0.35), 1.0)
	var slow_schedule := OutcomeSchedule.compile(slow, _tempo(0.8, 0.7), 1.0)

	assert_eq(_order(slow), _order(fast), "the landing sequence must not move")
	assert_eq(_amounts(slow), _amounts(fast), "nor may any number")
	for i in fast_schedule.entries.size():
		assert_almost_eq(slow_schedule.entries[i].arrive_at,
				fast_schedule.entries[i].arrive_at * 2.0, 0.0001,
				"entry %d's arrival must double" % i)
		assert_almost_eq(slow_schedule.entries[i].launch_at,
				fast_schedule.entries[i].launch_at * 2.0, 0.0001,
				"entry %d's launch must double" % i)
	assert_almost_eq(slow_schedule.duration(), fast_schedule.duration() * 2.0, 0.0001)


## The same claim through the PLAYER's half of the tempo split (D3b): the rate
## is a per-peer [member GameSettings.combat_time_scale], so it is the one that
## genuinely differs between two machines mid-cast.
func test_the_player_rate_scales_seconds_and_nothing_else() -> void:
	var normal := _beat_outcome()
	var half_speed := _beat_outcome()
	var a := OutcomeSchedule.compile(normal, _tempo(0.4, 0.35), 1.0)
	var b := OutcomeSchedule.compile(half_speed, _tempo(0.4, 0.35), 2.0)
	assert_eq(_order(half_speed), _order(normal))
	for i in a.entries.size():
		assert_eq(b.entries[i].index, a.entries[i].index,
				"the structural index is identical on every peer, by construction")
		assert_almost_eq(b.entries[i].arrive_at, a.entries[i].arrive_at * 2.0, 0.0001)


func test_the_sort_key_is_the_entry_index_and_ties_keep_append_order() -> void:
	# Three landings sharing one beat: one entry, so all three tie and the
	# original-index tiebreak is the only thing ordering them.
	var outcome := AttackOutcome.new()
	outcome.cadence = ScheduleEntry.Cadence.BEAT
	var ev := PropagationEvent.new()
	var expected: Array[HitInstance] = []
	for i in 3:
		var hit := DamageInstance.new()
		hit.structural_key = 0.0
		outcome.hits.append(hit)
		ev.hits.append(hit)
		expected.append(hit)
	outcome.timeline.append(ev)
	OutcomeSchedule.compile(outcome, _tempo(0.4, 0.35), 1.0)
	for hit in outcome.hits:
		assert_eq(hit.schedule_index, 0, "one beat is one entry")
	assert_eq(OutcomeApplier.in_arrival_order(outcome.hits), expected,
			"a whole-wave tie is a provable no-op")


## The other half of D2: [CritRoll] draws one seeded stream in landing order,
## so if that order were seconds-keyed the same seed would deal different crits
## on two peers running combat at different speeds — off the same structure.
func test_the_crit_stream_is_order_stable_under_a_tempo_change() -> void:
	var fast := _resolved_line_cast(_tempo(0.4, 0.35))
	var slow := _resolved_line_cast(_tempo(4.0, 1.0))
	var fast_outcome: AttackOutcome = fast.outcome
	var slow_outcome: AttackOutcome = slow.outcome

	assert_gt(fast_outcome.hits.size(), 1, "precondition: a multi-landing cast")
	assert_gt(slow_outcome.schedule.duration(), fast_outcome.schedule.duration(),
			"precondition: the two really are at different tempos")

	var fast_crits: Array = []
	var slow_crits: Array = []
	for hit in OutcomeApplier.in_arrival_order(fast_outcome.hits):
		fast_crits.append([hit.is_crit, hit.crit_tier, hit.crit_multiplier])
	for hit in OutcomeApplier.in_arrival_order(slow_outcome.hits):
		slow_crits.append([hit.is_crit, hit.crit_tier, hit.crit_multiplier])
	assert_eq(slow_crits, fast_crits,
			"same seed + same structure + different tempo == identical crits")


# -- D1: the compiler is arrival_time's sole writer ---------------------------

## Acceptance: "the three resolver writes to `arrival_time` are gone; a test
## asserts the compiler is its sole writer."
##
## A source scan, deliberately. A behavioural test can only show that the
## number is currently right; what actually regresses is somebody re-adding a
## convenient stamp in a mode, which would still LOOK right until two peers
## disagreed about tempo. This fails the moment one comes back.
func test_no_mode_writes_arrival_time() -> void:
	for path in _MODE_SOURCES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "could not read %s" % path)
		for line in text.split("\n"):
			var code: String = line.strip_edges()
			if code.begins_with("#"):
				continue
			assert_false(code.contains("arrival_time ="),
					"%s writes arrival_time — the compiler is its sole writer (#543 D1): %s"
							% [path, code])


## The D2 grep, run as a test rather than left to a reviewer's eye: nothing
## anywhere sorts or compares on seconds.
func test_nothing_orders_on_arrival_time() -> void:
	var ordering_sources: Array[String] = [
		"res://attack/outcome/outcome_applier.gd",
		"res://attack/outcome/crit_roll.gd",
		"res://attack/outcome/outcome_schedule.gd",
	]
	for path in ordering_sources:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "could not read %s" % path)
		for line in text.split("\n"):
			var code: String = line.strip_edges()
			if code.begins_with("#") or code.begins_with("##"):
				continue
			if not code.contains("arrival_time"):
				continue
			# Two legal mentions, and only two: the compiler's write-back, and
			# the applier WAITING on seconds — which is the whole point of the
			# split. Ordering is structure; the wait is presentation.
			var legal := (code.begins_with("hit.arrival_time = entry.arrive_at")
					or code.begins_with("await beat.advance_to(hit.arrival_time)"))
			assert_true(legal,
					"%s reads arrival_time outside the write/wait pair: %s" % [path, code])


func test_the_compiler_assigns_seconds_that_were_never_stamped() -> void:
	var outcome := _beat_outcome()
	for hit in outcome.hits:
		assert_almost_eq(hit.arrival_time, 0.0, 0.0001,
				"nothing has assigned seconds yet")
		assert_eq(hit.schedule_index, -1, "nor an order")
	OutcomeSchedule.compile(outcome, _tempo(0.4, 0.35), 1.0)
	for hit in outcome.hits:
		assert_gt(hit.arrival_time, 0.0, "the compiler wrote seconds")
		assert_gte(hit.schedule_index, 0, "and an order")


# -- D4: structure crosses the wire, seconds never do -------------------------

## Acceptance: "AttackRecord no longer serializes absolute seconds. A
## round-trip test encodes on one tempo, decodes under a different tempo, and
## asserts identical landing order and identical damage."
func test_a_record_round_trips_across_tempos_with_identical_order_and_damage() -> void:
	var cast := _resolved_line_cast(_tempo(0.4, 0.35))
	var graph: Graph = cast.graph
	var host: AttackOutcome = cast.outcome
	var wire := AttackRecord.capture(host, graph)

	assert_false(wire.has("h_at"), "seconds must not be on the wire")
	assert_true(wire.has(AttackRecord.KEY_HIT_STRUCT), "structure must be")

	var peer := AttackRecord.rebuild(wire, graph)
	# Recompile the peer's own seconds at a wildly different tempo — the
	# situation D4 legalises and D2 is what makes safe.
	peer.schedule = OutcomeSchedule.compile(peer, _tempo(3.0, 1.5), 2.0)

	assert_eq(_order(peer), _order(host), "identical landing order")
	assert_eq(_amounts(peer), _amounts(host), "identical damage")
	assert_gt(peer.schedule.duration(), host.schedule.duration(),
			"the peer really is playing it slower")


func test_the_cadence_and_the_tempo_shape_cross_the_wire() -> void:
	var cast := _resolved_line_cast()
	var peer := AttackRecord.rebuild(AttackRecord.capture(cast.outcome, cast.graph), cast.graph)
	assert_eq(peer.cadence, ScheduleEntry.Cadence.BEAT,
			"a peer must know which arithmetic to run")
	assert_not_null(peer.schedule, "rebuild mints the peer's own seconds")


# -- D6: the entry carries render context -------------------------------------

## Acceptance names `visit_index` in particular: "a node struck 3+ times
## reports 0,1,2". A self-loop with `max_visits_per_node = 3` is the
## Reverberator shape in miniature.
func test_visit_index_counts_repeat_strikes_on_one_node() -> void:
	var graph := _h.make_graph([[0, 1], [1, 1]], self)
	var nodes := graph.get_skill_nodes()
	var attacker := _h.make_entity(graph, "Attacker", Color.RED)
	var defender := _h.make_entity(graph, "Defender", Color.BLUE)
	_h.give_big_hp(defender)
	_h.assign_owner(graph, attacker, [0])
	_h.assign_owner(graph, defender, [1])
	var config := _h.make_config(_h.fan_all(), _h.owner_enemy(), null,
			{max_hops = 3, max_visits_per_node = 3})
	var spell := _h.make_spell(config, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, nodes[1], nodes[0], attacker, graph)

	var visits: Array = []
	for entry in outcome.schedule.entries:
		if entry.target == nodes[1]:
			visits.append(entry.visit_index)
	assert_eq(visits, [0, 1, 2],
			"the nth strike on a node reports n-1 — Reverberator's whole read")


func test_every_d6_field_is_populated_on_a_real_cast() -> void:
	var outcome: AttackOutcome = _resolved_line_cast(_tempo(0.4, 0.35)).outcome
	var schedule := outcome.schedule
	assert_gt(schedule.entries.size(), 2, "precondition: a multi-beat cast")

	var beat_counts: Array = []
	var terminal_seen := false
	for entry in schedule.entries:
		assert_eq(entry.beat_count, schedule.entries.size(),
				"beat_count is the whole cast's wave count")
		assert_gte(entry.convergence_count, 1, "convergence is at least the one predecessor")
		assert_gte(entry.visit_index, 0)
		assert_between(entry.magnitude, 0.0, 1.0,
				"magnitude is normalized against the cast's biggest landing")
		assert_between(entry.beat_fraction(), 0.0, 1.0)
		assert_gte(entry.arrive_at, entry.launch_at,
				"launch_at/arrive_at are a window, not a pair of unrelated instants")
		assert_almost_eq(entry.window(), entry.arrive_at - entry.launch_at, 0.0001)
		beat_counts.append(entry.beat_index)
		terminal_seen = terminal_seen or entry.is_terminal

	assert_eq(beat_counts, [0, 1, 2], "beat_index ascends with the walk")
	assert_true(terminal_seen, "the walk ended somewhere — is_terminal marks where")
	# 1.0 must actually be reached, or "normalized" is a word rather than a fact.
	var peak := 0.0
	for entry in schedule.entries:
		peak = maxf(peak, entry.magnitude)
	assert_almost_eq(peak, 1.0, 0.0001, "the biggest landing reports 1.0")


func test_the_terminal_entry_is_where_the_walk_ended_not_merely_the_last_one() -> void:
	var outcome: AttackOutcome = _resolved_line_cast().outcome
	var last: ScheduleEntry = outcome.schedule.entries[-1]
	assert_true(last.is_terminal,
			"a line cast that runs out of hops ends at its furthest landing")


# -- D7: compile from the timeline, not from the hits -------------------------

## Acceptance: "a pure-utility (`power` 0) spell and a CANCEL event both still
## produce schedule entries." A hits-derived schedule would no-op the first and
## drop the second, silently.
func test_a_pure_utility_cast_still_produces_entries() -> void:
	var outcome: AttackOutcome = _resolved_line_cast(null, 0.0).outcome
	assert_gt(outcome.timeline.size(), 0, "precondition: the walk still happened")
	assert_eq(outcome.schedule.entries.size(), outcome.timeline.size(),
			"one entry per landing moment, damage or not")
	for entry in outcome.schedule.entries:
		assert_almost_eq(entry.magnitude, 0.0, 0.0001,
				"nothing landed, so nothing is the biggest thing that landed")


func test_a_cancel_event_still_produces_an_entry() -> void:
	# Diamond: 0 -> 1, two branches reconverge on 3, where CancelIfMulti fizzles.
	var graph := _h.make_graph([[0, 1], [1, 2], [1, 4], [2, 3], [4, 3]], self)
	var nodes := graph.get_skill_nodes()
	var attacker := _h.make_entity(graph, "Attacker", Color.RED)
	var defender := _h.make_entity(graph, "Defender", Color.BLUE)
	_h.give_big_hp(defender)
	_h.assign_owner(graph, attacker, [0])
	_h.assign_owner(graph, defender, [1, 2, 3, 4])
	var config := _h.make_config(_h.fan_all(), _h.owner_enemy(), _h.cancel_if_multi(),
			{max_hops = 2})
	var spell := _h.make_spell(config, [DamageEffect.new()], 10.0)
	var outcome := SpellResolver.resolve(spell, nodes[1], nodes[0], attacker, graph)

	var cancels := 0
	var cancel_entries := 0
	for ev in outcome.timeline:
		if ev.verb == PropagationEvent.Verb.CANCEL:
			cancels += 1
	for entry in outcome.schedule.entries:
		if entry.event != null and entry.event.verb == PropagationEvent.Verb.CANCEL:
			cancel_entries += 1
			assert_true(entry.hits.is_empty(), "a CANCEL carries no landing")
			assert_almost_eq(entry.magnitude, 0.0, 0.0001)
	assert_gt(cancels, 0, "precondition: the reducer really fizzled something")
	assert_eq(cancel_entries, cancels, "every cancel pop gets its own beat")
