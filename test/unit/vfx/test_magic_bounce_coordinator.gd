extends GutTest

## Clock-contract tests for [MagicBounceCoordinator]. The propagation clock
## is fixed (one wave per [member MagicBounceCoordinator.beat_interval])
## and animations may NOT gate it — so these tests assert on the
## [signal MagicBounceCoordinator.wave_started] emission cadence, not on
## projectile completion.
##
## Tests cover: three-clocks scheduling (#201), verb→ProjectilePath mapping,
## CANCEL dissipate, and the legacy fallback path.

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


func _mount_coord(beat_interval: float, launch_to_impact: float, visual: PackedScene = null) -> MagicBounceCoordinator:
	var coord := MagicBounceCoordinator.new()
	coord.beat_interval = beat_interval
	coord.launch_to_impact = launch_to_impact
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
	# Drive the scheduler past the last hop with margin. The span is now
	# `launch_to_impact + 3 * beat_interval` — beat 0 waits for the seed bolt to
	# actually arrive before it is announced — and every sub-frame timer in here
	# rounds up to a whole headless frame, so the margin is generous on purpose.
	await get_tree().create_timer(0.06 * 8).timeout
	assert_eq(events.size(), 4, "one wave per hop index 0..3")
	for i in 4:
		assert_eq(int(events[i].hop), i, "wave %d emitted hop_index %d" % [i, i])
		assert_eq(int(events[i].count), 1,
				"line-graph wave %d should have exactly one hit" % i)


func test_wave_intervals_match_beat_interval() -> void:
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


func test_damage_shown_fires_per_beat_not_synchronously_with_play() -> void:
	# #481: Events.damage_shown must fire on the propagation clock (at each
	# beat's wave_started), not the instant play() is called — mirrors
	# test_wave_started_fires_once_per_hop_in_order's shape.
	var nodes := _graph.get_skill_nodes()
	var beats := [0, 1, 1, 2]
	var outcome := AttackOutcome.new()
	for i in beats.size():
		var ev := PropagationEvent.new()
		ev.beat = int(beats[i])
		ev.origin = nodes[0]
		ev.target = nodes[1]
		var hit := DamageInstance.new()
		hit.origin = nodes[0]
		hit.target = nodes[1]
		hit.amount = 3.0
		hit.effective_amount = 3.0
		ev.damage = hit
		outcome.hits.append(hit)
		outcome.timeline.append(ev)
	var coord := _mount_coord(0.04, 0.03)
	var shown: Array = []
	var handler := func(target: SkillNode, amount: float) -> void:
		shown.append([target, amount])
	Events.damage_shown.connect(handler)
	coord.play(outcome)
	# Beat 0 does NOT reveal synchronously with play(): its own bolt is still
	# in the air. The seed hop gets the same treatment every later hop already
	# got — spawn, fly `launch_to_impact`, then announce — so nothing is
	# revealed at all in the frame play() was called, and the first
	# propagation cannot leave a target the bolt hasn't reached yet.
	assert_eq(shown.size(), 0, "no reveal before the seed bolt has flown")
	await get_tree().create_timer(0.04 * 8).timeout
	Events.damage_shown.disconnect(handler)
	assert_eq(shown.size(), 4, "one reveal per timeline event across 3 beats")
	for entry in shown:
		assert_eq(entry[0], nodes[1])
		assert_eq(entry[1], 3.0)


func test_coordinator_never_mutates_hp() -> void:
	# #474: the coordinator is a PURE OBSERVER — BattleSystem applies the
	# whole AttackOutcome synchronously before play() ever runs, so a
	# damage-bearing landing must NOT change HP here, and neither must a
	# null-damage (utility) landing. Projectile timing is CPU, so this runs
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
	assert_eq(nodes[1].get_current_hp(), hp1_before,
			"the coordinator must not apply the hit's damage itself")
	assert_eq(nodes[2].get_current_hp(), hp2_before,
			"null-damage event applied no HP to node 2")


# -- Verb → path mapping ------------------------------------------------------

func test_verb_jump_uses_jump_path() -> void:
	var nodes := _graph.get_skill_nodes()
	var jump_path := BezierArcPath.new()
	jump_path.apex_height = 999.0
	var coord := _mount_coord(0.05, 0.03)
	coord.jump_path = jump_path
	coord.edge_path = LinearPath.new()

	var outcome := _make_single_event_outcome(nodes, PropagationEvent.Verb.JUMP)
	coord.play(outcome)
	await get_tree().create_timer(0.15).timeout

	var projectiles := _find_projectiles(coord)
	assert_eq(projectiles.size(), 1, "one projectile for JUMP event")
	assert_eq(projectiles[0].path, jump_path, "JUMP uses jump_path")


func test_verb_edge_uses_edge_path() -> void:
	var nodes := _graph.get_skill_nodes()
	var edge_path := LinearPath.new()
	var coord := _mount_coord(0.05, 0.03)
	coord.edge_path = edge_path

	var outcome := _make_single_event_outcome(nodes, PropagationEvent.Verb.EDGE)
	coord.play(outcome)
	await get_tree().create_timer(0.15).timeout

	var projectiles := _find_projectiles(coord)
	assert_eq(projectiles.size(), 1, "one projectile for EDGE event")
	assert_eq(projectiles[0].path, edge_path, "EDGE uses edge_path")


func test_verb_self_loop_uses_self_loop_path() -> void:
	var nodes := _graph.get_skill_nodes()
	var slp := SelfLoopPath.new()
	slp.loop_height = 80.0
	var coord := _mount_coord(0.05, 0.03)
	coord.self_loop_path = slp

	var outcome := _make_single_event_outcome(nodes, PropagationEvent.Verb.SELF_LOOP)
	coord.play(outcome)
	await get_tree().create_timer(0.15).timeout

	var projectiles := _find_projectiles(coord)
	assert_eq(projectiles.size(), 1, "one projectile for SELF_LOOP event")
	assert_eq(projectiles[0].path, slp, "SELF_LOOP uses self_loop_path")


func test_unset_verb_path_falls_back_to_projectile_path() -> void:
	var nodes := _graph.get_skill_nodes()
	var fallback := BezierArcPath.new()
	fallback.apex_height = 500.0
	var coord := _mount_coord(0.05, 0.03)
	coord.projectile_path = fallback
	# Don't set edge_path — should fall back.

	var outcome := _make_single_event_outcome(nodes, PropagationEvent.Verb.EDGE)
	coord.play(outcome)
	await get_tree().create_timer(0.15).timeout

	var projectiles := _find_projectiles(coord)
	assert_eq(projectiles.size(), 1, "one projectile for EDGE event")
	assert_eq(projectiles[0].path, fallback, "EDGE falls back to projectile_path")


# -- CANCEL dissipate ---------------------------------------------------------

func test_cancel_event_spawns_dissipate_visual() -> void:
	var nodes := _graph.get_skill_nodes()
	var coord := _mount_coord(0.05, 0.03)

	var outcome := _make_single_event_outcome(nodes, PropagationEvent.Verb.CANCEL)
	coord.play(outcome)
	await get_tree().create_timer(0.15).timeout

	# A CANCEL event should spawn a non-Projectile child (a CancelDissipate).
	var has_dissipate := false
	for child in coord.get_children():
		if not child is Projectile:
			has_dissipate = true
			break
	assert_true(has_dissipate, "CANCEL spawns a non-projectile dissipate visual")


func test_cancel_dissipate_is_at_target_position() -> void:
	var nodes := _graph.get_skill_nodes()
	var coord := _mount_coord(0.05, 0.03)

	var outcome := _make_single_event_outcome(nodes, PropagationEvent.Verb.CANCEL)
	coord.play(outcome)
	await get_tree().create_timer(0.15).timeout

	for child in coord.get_children():
		if not child is Projectile:
			assert_eq(child.global_position, nodes[1].global_position,
					"dissipate is at the target node")
			break


func test_cancel_event_with_null_visual_does_not_spawn() -> void:
	var nodes := _graph.get_skill_nodes()
	var coord := _mount_coord(0.05, 0.03)
	coord.cancel_visual = null

	var outcome := _make_single_event_outcome(nodes, PropagationEvent.Verb.CANCEL)
	coord.play(outcome)
	await get_tree().create_timer(0.15).timeout

	var non_projectile_count := 0
	for child in coord.get_children():
		if not child is Projectile:
			non_projectile_count += 1
	assert_eq(non_projectile_count, 0, "null cancel_visual spawns nothing")


# -- Three-clocks: wave_started still fires at beat cadence -------------------

func test_three_clocks_impact_pinned_to_beat() -> void:
	# With beat_interval=0.10 and launch_to_impact=0.04, wave_started fires
	# at t=0, t=0.10, t=0.20, t=0.30 for 4 beats. This is the same cadence
	# as before the rename — the three-clocks scheduling doesn't change the
	# wave clock, only when projectiles are spawned (which is internal).
	var outcome := _build_4hop_outcome()
	var coord := _mount_coord(0.10, 0.04)
	var events: Array = []
	coord.wave_started.connect(func(hop: int, _c: int) -> void:
		events.append(hop))
	coord.play(outcome)
	await get_tree().create_timer(0.10 * 5).timeout
	assert_eq(events.size(), 4, "all 4 waves fire on three-clocks schedule")
	assert_eq(events, [0, 1, 2, 3])


## `play()` must not return until the WHOLE timeline has run. AttackVFX frees
## the coordinator the moment `await coord.play(payload)` resolves, so an early
## return silently drops every later beat and the `take_damage` lambdas riding
## its projectiles.
##
## Driven by the deterministic trigger rather than a timing race: a first beat
## that spawns NOTHING. `_play_cancel` returns before touching the counter when
## `cancel_visual` is null, so `pending` is still 0 the first time the drain
## checks it and the loop falls straight through — at any tuning, no reliance on
## how long a projectile lingers before it frees. (The other trigger,
## `beat_interval > 2 * launch_to_impact`, is real but races the visual's linger
## and does not make a stable test.)
##
## Every other test in this file calls `play()` bare and waits on a wall-clock
## timer, so none of them can see this — the assertion has to be on what has
## happened *by the time play() resolves*.
func test_play_does_not_return_before_the_last_beat() -> void:
	var nodes := _graph.get_skill_nodes()
	var coord := _mount_coord(0.05, 0.03)
	coord.cancel_visual = null  # beat 0 will spawn nothing at all

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
	hit_ev.damage = hit
	outcome.hits.append(hit)
	outcome.timeline.append(hit_ev)

	var events: Array = []
	coord.wave_started.connect(func(hop: int, _c: int) -> void:
		events.append(hop))

	await coord.play(outcome)

	assert_eq(events, [0, 1],
		"play() resolved after only %d of 2 beats — AttackVFX frees the " % events.size()
			+ "coordinator here, so the rest of the timeline (and its damage) is dropped")


# -- Helpers ------------------------------------------------------------------

func _make_single_event_outcome(nodes: Array, verb: PropagationEvent.Verb) -> AttackOutcome:
	var outcome := AttackOutcome.new()
	var ev := PropagationEvent.new()
	ev.beat = 0
	ev.verb = verb
	ev.origin = nodes[0]
	ev.target = nodes[1]
	if verb != PropagationEvent.Verb.CANCEL:
		var hit := DamageInstance.new()
		hit.origin = nodes[0]
		hit.target = nodes[1]
		hit.amount = 1.0
		ev.damage = hit
		outcome.hits.append(hit)
	outcome.timeline.append(ev)
	return outcome


func _find_projectiles(coord: MagicBounceCoordinator) -> Array[Projectile]:
	var result: Array[Projectile] = []
	for child in coord.get_children():
		if child is Projectile:
			result.append(child)
	return result
