extends GutTest

## #619 — SkillBlade.play() gains a playback_rate knob. The one real
## correctness trap (per the issue): the tween's callback argument must stay
## trajectory time, never wall-clock time, so hit scheduling (BladeHitEvent.t)
## is unaffected by the rate. See the sim/presentation invariant in
## docs/domain/melee-blade-sim.md.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

const _DT := 0.05
const _STEPS := 6  # trajectory duration = 0.30s — long enough that
                    # frame-granularity jitter is a small fraction of it.


func _blade_fixture() -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var member := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(member)
	member.position = Vector2(80.0, 0.0)
	await get_tree().process_frame
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var nodes: Array[SkillNode] = [pivot, member]
	blade.build_from_skill_nodes(nodes, pivot, [[pivot, member]], null)
	# Godot's first Tween after a fresh node enters the tree runs on a skewed
	# initial delta — measured over 3x the requested duration in isolation, and
	# unpredictably SHORT here depending on GUT's own frame timing. Settle it
	# with a throwaway ghost play() so every timed play() in a test runs on
	# steady-state footing (measured: sub-1ms jitter once warm).
	await blade.play(_traj_fixture(), [], true)
	return {"blade": blade, "member": member}


## Every sample is the same pose — motion is irrelevant to timing/scheduling,
## which is all these tests exercise.
func _traj_fixture() -> BladeTrajectory:
	var traj := BladeTrajectory.new()
	traj.sample_dt = _DT
	traj.samples = []
	for k in range(_STEPS + 1):
		traj.samples.append(PackedVector2Array([Vector2.ZERO, Vector2(80.0, 0.0)]))
	return traj


func _recorded_hit_times(
		blade: SkillBlade, traj: BladeTrajectory,
		hits: Array[BladeHitEvent], rate: float) -> Array[float]:
	var seen: Array[float] = []
	var cb := func(_p: int, _e: bool, _tgt: SkillNode, t: float, _d: float) -> void:
		seen.append(t)
	blade.hit.connect(cb)
	await blade.play(traj, hits, false, rate)
	blade.hit.disconnect(cb)
	return seen


## Headless Godot doesn't run Tween time 1:1 against Time.get_ticks_msec (the
## main loop iterates as fast as the CPU allows), so this compares the DEFAULT
## call against an EXPLICIT rate=1.0 call rather than against traj.duration()
## in absolute wall-clock terms — whatever the environment's scale factor is,
## it applies equally to both measurements.
func test_default_rate_matches_an_explicit_rate_of_one() -> void:
	var fx := await _blade_fixture()
	var blade: SkillBlade = fx.blade
	var traj := _traj_fixture()

	var t0 := Time.get_ticks_msec()
	await blade.play(traj)  # no rate passed — must behave exactly as before #619
	var default_ms := Time.get_ticks_msec() - t0

	var t1 := Time.get_ticks_msec()
	await blade.play(traj, [], false, 1.0)
	var explicit_ms := Time.get_ticks_msec() - t1

	assert_almost_eq(float(default_ms), float(explicit_ms), maxf(float(explicit_ms) * 0.35, 25.0),
			"the default rate must behave exactly like an explicit 1.0x rate (#619)")


func test_half_rate_takes_twice_the_wall_clock_and_finishes_once() -> void:
	var fx := await _blade_fixture()
	var blade: SkillBlade = fx.blade
	var traj := _traj_fixture()
	watch_signals(blade)

	var t0 := Time.get_ticks_msec()
	await blade.play(traj, [], false, 1.0)
	var full_ms := Time.get_ticks_msec() - t0

	var t1 := Time.get_ticks_msec()
	await blade.play(traj, [], false, 0.5)
	var half_ms := Time.get_ticks_msec() - t1

	assert_almost_eq(float(half_ms), float(full_ms) * 2.0, float(full_ms) * 0.5,
			"a 0.5x rate must take ~2x the wall-clock of a 1.0x rate (#619)")
	assert_signal_emit_count(blade, "playback_finished", 2,
			"exactly one playback_finished per play() call — never a double-fire under a rate knob")


## The trap: a rate knob must not shift hit scheduling into wall-clock time.
## Same events, same trajectory, two different rates — the reported `t` on
## every `hit` signal must be identical either way, because BladeHitEvent.t
## is always trajectory-domain, never wall-clock.
func test_hit_events_fire_at_the_same_trajectory_t_at_any_rate() -> void:
	var fx := await _blade_fixture()
	var blade: SkillBlade = fx.blade
	var member: SkillNode = fx.member
	var traj := _traj_fixture()
	var hits: Array[BladeHitEvent] = [
		BladeHitEvent.new(_DT * 1.0, 1, -1, member),
		BladeHitEvent.new(_DT * 4.0, 1, -1, member),
	]

	var ts_full := await _recorded_hit_times(blade, traj, hits, 1.0)
	var ts_half := await _recorded_hit_times(blade, traj, hits, 0.5)

	assert_eq(ts_full, [_DT * 1.0, _DT * 4.0],
			"hits must fire with the event's own scheduled t, unmodified")
	assert_eq(ts_full, ts_half,
			"the SAME trajectory-t hit sequence must fire regardless of playback_rate (#619)")
