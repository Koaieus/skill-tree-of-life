extends GutTest
## #1003: [SwingResolve] resolves a swing from a hand-built [SwingContext] —
## no [MeleeAttackPlan] anywhere. The plan is one BUILDER of a context; the
## engine must not need it.

const _SEED: int = 0xBEEF


func _spine_state() -> BladeState:
	var positions: Array[Vector2] = [
			Vector2.ZERO, Vector2(50, 0), Vector2(100, 0), Vector2(150, 0)]
	var radii: Array[float] = [16.0, 16.0, 16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)]
	var s := BladeState.build(positions, 0, edges, radii)
	for i in 4:
		s.vertex_damage[i] = 3.0
		s.vertex_blunting[i] = 1.0
	return s


func _context(state: BladeState) -> SwingContext:
	var ctx := SwingContext.new()
	ctx.state = state
	if state != null:
		var pivot_pos := state.positions[state.pivot_index]
		var offset := state.positions[1] - pivot_pos
		ctx.drivers = [BladeArcDriver.new(
				1, pivot_pos, offset.length(), offset.angle(), TAU, ctx.swing_duration)]
	ctx.world = CombatWorld.shadow()
	ctx.resolve_seed = _SEED
	return ctx


func test_a_plan_free_context_resolves_a_whole_swing() -> void:
	var ctx := _context(_spine_state())
	var run := SwingResolve.new(ctx)
	assert_false(run.is_done(), "a runnable context starts un-done")
	assert_true(run.advance(0), "an unbounded budget resolves the rest of the swing")
	var expected_steps := int(ceil(ctx.swing_duration / ctx.dt))
	assert_eq(run.result.trajectory.samples.size(), expected_steps + 1,
			"the start pose plus one sample per step")
	assert_almost_eq(run.progress(), 1.0, 0.0001)
	assert_almost_eq(run.total_duration(), float(expected_steps) * ctx.dt, 0.0001)
	assert_eq(run.result.outcome.resolve_seed, _SEED, "the outcome carries the context's seed")
	assert_eq(run.result.outcome.cadence, ScheduleEntry.Cadence.SWING)
	assert_not_null(run.result.live_gate)
	assert_not_null(run.result.outcome.schedule,
			"a finished run compiles its schedule")
	assert_true(run.result.hits.is_empty(), "no space state, nothing to scan, nothing lands")
	ctx.world.free_shadow()


func test_a_sliced_run_reaches_the_same_end() -> void:
	var whole_ctx := _context(_spine_state())
	var whole := SwingResolve.new(whole_ctx)
	whole.advance(0)
	var sliced_ctx := _context(_spine_state())
	var sliced := SwingResolve.new(sliced_ctx)
	var slices := 0
	while not sliced.advance(7):
		slices += 1
		assert_lt(sliced.progress(), 1.0, "mid-flight progress is under 1")
	assert_gt(slices, 1, "a budget of 7 samples takes several slices")
	assert_eq(sliced.result.trajectory.samples.size(), whole.result.trajectory.samples.size())
	assert_eq(sliced.result.trajectory.samples[-1], whole.result.trajectory.samples[-1],
			"a slice boundary is bit-identical to none")
	whole_ctx.world.free_shadow()
	sliced_ctx.world.free_shadow()


func test_a_null_state_is_done_on_construction() -> void:
	var ctx := _context(null)
	var run := SwingResolve.new(ctx)
	assert_true(run.is_done(), "nothing to swing: done before the first step")
	assert_true(run.advance(0))
	assert_null(run.result.trajectory, "an invalid swing has no trajectory")
	assert_eq(run.result.outcome.resolve_seed, _SEED, "but its outcome still carries the seed")
	ctx.world.free_shadow()
