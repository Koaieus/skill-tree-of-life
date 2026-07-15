extends GutTest

## Clock-contract tests for [MagicBounceCoordinator]. The propagation clock
## is fixed (one wave per [member MagicBounceCoordinator.per_hop_duration])
## and animations may NOT gate it — so these tests assert on the
## [signal MagicBounceCoordinator.wave_started] emission cadence, not on
## projectile completion.

const STUB_NEVER_FINISH := preload("res://test/unit/vfx/stub_never_finish_visual.tscn")

var _helper: SpellTestHelper
var _graph: Graph
var _attacker: Entity
var _defender: Entity


func before_each() -> void:
	_helper = SpellTestHelper.new()
	# Line graph: A(0) — B(1) — C(2) — D(3) — E(4).
	_graph = _helper.make_graph([[0, 1], [1, 2], [2, 3], [3, 4]], self)
	_attacker = _helper.make_entity(_graph, "Attacker", Color.RED)
	_defender = _helper.make_entity(_graph, "Defender", Color.BLUE)
	_helper.give_big_hp(_defender)
	_helper.assign_owner(_graph, _attacker, [0])
	_helper.assign_owner(_graph, _defender, [1, 2, 3, 4])


# Build a 4-hop outcome (hop indices 0..3) via the real resolver, so the
# `hop_index` on each hit is wired exactly the way production produces it.
# On a line graph with FanAll + enemy-only + max_visits=1, the wave at each
# hop is a single hit, which keeps the assertions tight.
func _build_4hop_outcome() -> AttackOutcome:
	var config := _helper.make_config(
			_helper.fan_all(), _helper.owner_enemy(), null,
			{max_hops = 3})
	var spell := _helper.make_spell(config, [DamageEffect.new()], 100.0)
	var nodes := _graph.get_skill_nodes()
	return SpellResolver.resolve(spell, nodes[1], nodes[0], _attacker, _graph)


func _mount_coord(per_hop: float, flight: float, visual: PackedScene = null) -> MagicBounceCoordinator:
	var coord := MagicBounceCoordinator.new()
	coord.per_hop_duration = per_hop
	coord.flight_time = flight
	if visual != null:
		coord.visual_scene = visual
	add_child_autofree(coord)
	return coord


func test_resolver_produces_monotonic_hop_indices() -> void:
	# Sanity: the helper-built outcome carries hop_index 0..3 in order on
	# this line graph. Pinned so a resolver regression doesn't silently
	# turn the timing tests into nonsense assertions.
	var outcome := _build_4hop_outcome()
	assert_eq(outcome.hits.size(), 4)
	for i in 4:
		var src: Variant = outcome.hits[i].source
		assert_true(src is CastSpell, "hit %d source should be CastSpell" % i)
		assert_eq((src as CastSpell).hop_index, i,
				"hit %d should be hop %d" % [i, i])


func test_wave_started_fires_once_per_hop_in_order() -> void:
	var outcome := _build_4hop_outcome()
	var coord := _mount_coord(0.06, 0.04)
	var events: Array = []
	coord.wave_started.connect(func(hop: int, count: int) -> void:
		events.append({"hop": hop, "count": count}))
	coord.play(outcome)
	# Drive the scheduler past the last hop with margin.
	await get_tree().create_timer(0.06 * 5).timeout
	assert_eq(events.size(), 4, "one wave per hop index 0..3")
	for i in 4:
		assert_eq(int(events[i].hop), i, "wave %d emitted hop_index %d" % [i, i])
		assert_eq(int(events[i].count), 1,
				"line-graph wave %d should have exactly one hit" % i)


func test_wave_intervals_match_per_hop_duration() -> void:
	# We assert TOTAL elapsed time (first → last emission) rather than
	# per-interval deltas: the first emission has variable startup delay
	# (the play() coroutine is launched bare, picked up by the message
	# pump on the next frame boundary). The total span cancels that out
	# — what matters for the clock contract is the average cadence.
	var outcome := _build_4hop_outcome()
	var dur := 0.08
	var coord := _mount_coord(dur, 0.05)
	var stamps: Array[int] = []
	coord.wave_started.connect(func(_h: int, _c: int) -> void:
		stamps.append(Time.get_ticks_msec()))
	coord.play(outcome)
	await get_tree().create_timer(dur * 5).timeout
	assert_eq(stamps.size(), 4)
	var total_ms: int = stamps[3] - stamps[0]
	var expected_total_ms: int = int(dur * 1000.0) * 3
	# Tolerance: ±1 frame per interval, plus 10ms headless slack.
	var tol_ms := 3 * 20 + 10
	assert_true(absi(total_ms - expected_total_ms) <= tol_ms,
			"hops 0→3 elapsed %dms, expected ~%dms (±%dms)" % [
					total_ms, expected_total_ms, tol_ms])
	# Each interval should be strictly positive and bounded — a hop with
	# zero or negative gap would mean the wave clock collapsed.
	for i in range(1, stamps.size()):
		var delta_ms: int = stamps[i] - stamps[i - 1]
		assert_true(delta_ms > 0, "interval %d→%d must advance time" % [i - 1, i])
		assert_true(delta_ms < int(dur * 1000.0) * 3,
				"interval %d→%d ran away: %dms" % [i - 1, i, delta_ms])


func test_hung_visual_does_not_delay_subsequent_waves() -> void:
	# The whole point of the clock contract: a visual that never finishes
	# (`finished` signal never fires) keeps the projectile alive forever,
	# but MUST NOT hold up the next hop's wave_started emission. If this
	# test regresses, somebody re-introduced an `await previous-finished`
	# coupling — see feedback_spell_vfx_clock_contract memory.
	var outcome := _build_4hop_outcome()
	var dur := 0.05
	var coord := _mount_coord(dur, 0.04, STUB_NEVER_FINISH)
	var events: Array = []
	coord.wave_started.connect(func(hop: int, _c: int) -> void:
		events.append(hop))
	coord.play(outcome)
	await get_tree().create_timer(dur * 6).timeout
	assert_eq(events.size(), 4, "all 4 waves fire despite hung visuals")
	assert_eq(events, [0, 1, 2, 3])


func test_events_in_wave_grouped_by_beat() -> void:
	# Hand-built timeline: 4 events at beats [0, 1, 1, 2]. The coordinator
	# must emit 3 wave_started events with events_in_wave = [1, 2, 1].
	var nodes := _graph.get_skill_nodes()
	var beats := [0, 1, 1, 2]
	var outcome := AttackOutcome.new()
	for i in beats.size():
		var beat: int = int(beats[i])
		var ev := PropagationEvent.new()
		ev.beat = beat
		# Origin/target just need to be non-null SkillNodes; the coordinator
		# reads positions but doesn't care about the topology.
		ev.origin = nodes[0]
		ev.target = nodes[1]
		var hit := DamageInstance.new()
		hit.origin = nodes[0]
		hit.target = nodes[1]
		hit.amount = 1.0
		ev.damage = hit
		outcome.hits.append(hit)
		outcome.timeline.append(ev)
	var coord := _mount_coord(0.04, 0.03)
	var events: Array = []
	coord.wave_started.connect(func(hop: int, count: int) -> void:
		events.append([hop, count]))
	coord.play(outcome)
	await get_tree().create_timer(0.04 * 4).timeout
	assert_eq(events.size(), 3)
	assert_eq(events[0], [0, 1])
	assert_eq(events[1], [1, 2])
	assert_eq(events[2], [2, 1])


func test_arrival_applies_event_damage_and_null_event_applies_none() -> void:
	# The render path, not just the cadence: a projectile flies and applies
	# `ev.damage` on arrival. A null-damage (utility) event still spawns a
	# projectile but applies no HP. Projectile timing is CPU, so this runs
	# under the dummy renderer.
	var nodes := _graph.get_skill_nodes()
	var hp1_before := nodes[1].get_current_hp()
	var hp2_before := nodes[2].get_current_hp()
	var outcome := AttackOutcome.new()
	var hit := DamageInstance.new()
	hit.origin = nodes[0]
	hit.target = nodes[1]
	hit.amount = 5.0
	hit.type = DamageInstance.Type.MAGIC
	outcome.hits.append(hit)
	var ev1 := PropagationEvent.new()
	ev1.beat = 0
	ev1.origin = nodes[0]
	ev1.target = nodes[1]
	ev1.damage = hit
	outcome.timeline.append(ev1)
	var ev2 := PropagationEvent.new()  # utility landing: no damage
	ev2.beat = 0
	ev2.origin = nodes[0]
	ev2.target = nodes[2]
	ev2.damage = null
	outcome.timeline.append(ev2)
	var coord := _mount_coord(0.05, 0.03)
	coord.play(outcome)
	await get_tree().create_timer(0.25).timeout
	assert_true(nodes[1].get_current_hp() < hp1_before,
			"damage-bearing arrival dropped node 1's HP")
	assert_eq(nodes[2].get_current_hp(), hp2_before,
			"null-damage event applied no HP to node 2")
