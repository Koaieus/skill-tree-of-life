extends GutTest

## #787 — the blade pop VFX. `BladeNode.disabled: bool` (#256's interim de-lit)
## became `death_progress: float`, driven every playback frame by
## [SkillBlade] as a pure function of `(dead_at, t)` — never a fired-once
## Tween (`.claude/rules/presentation-clock.md`) — and a popped vertex spawns
## its shards into #835's [ShatterField] exactly once per pop, on the frame
## playback crosses its `dead_at`. Pins acceptance 1-5 from the issue's
## settled spec; the look itself is judged in the sandbox, per the issue's
## own note.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


func _build_blade(pop_window: float = 0.1) -> Dictionary:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var member := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(member)
	member.position = Vector2(80.0, 0.0)

	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var style: BladeStyle = BladeNode.DEFAULT_STYLE.duplicate(true) as BladeStyle
	style.pop_window = pop_window
	blade.style = style
	var nodes: Array[SkillNode] = [pivot, member]
	blade.build_from_skill_nodes(nodes, pivot, [[pivot, member]], null)
	return {"blade": blade, "pivot": pivot, "member": member}


## A trajectory where vertex 1 (the member) moves at a steady clip for a
## while, then goes still for the rest of the swing — the "post-death,
## inv_mass 0" shape [BladeState.remove_vertex] leaves behind, which
## [method SkillBlade.seed_velocity]'s walk-back has to see past.
func _traj_member_moves_then_stalls(
		dt: float, moving_steps: int, still_steps: int, vel: Vector2) -> BladeTrajectory:
	var traj := BladeTrajectory.new()
	traj.sample_dt = dt
	traj.samples = []
	var pos := Vector2.ZERO
	traj.samples.append(PackedVector2Array([Vector2.ZERO, pos]))
	for i in moving_steps:
		pos += vel * dt
		traj.samples.append(PackedVector2Array([Vector2.ZERO, pos]))
	for i in still_steps:
		traj.samples.append(PackedVector2Array([Vector2.ZERO, pos]))
	return traj


# ── Acceptance 1: death_progress ramps from dead_at over the window ─────────

func test_death_progress_ramps_from_dead_at_over_the_window() -> void:
	var setup := _build_blade(0.2)
	var blade: SkillBlade = setup.blade
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.dead_at[1] = 0.5
	var traj := _traj_member_moves_then_stalls(0.05, 20, 20, Vector2(100.0, 0.0))
	var visuals := blade.get_node_visuals()

	blade._apply_playback_frame(0.3, traj, [], true)
	assert_eq(visuals[1].death_progress, 0.0, "not dead yet")
	assert_eq(visuals[0].death_progress, 0.0, "the pivot is never in dead_at")

	blade._apply_playback_frame(0.6, traj, [], true)
	assert_almost_eq(visuals[1].death_progress, 0.5, 0.01, "halfway through the window")

	blade._apply_playback_frame(0.7, traj, [], true)
	assert_almost_eq(visuals[1].death_progress, 1.0, 0.0001, "fully gone at dead_at + window")

	blade._apply_playback_frame(1.0, traj, [], true)
	assert_almost_eq(visuals[1].death_progress, 1.0, 0.0001, "stays at 1.0 for the rest of the swing")
	assert_eq(visuals[0].death_progress, 0.0, "the pivot stayed 0 the whole swing")


# ── Acceptance 2: an edge follows its endpoint's progress ───────────────────

func test_edge_follows_its_dead_endpoints_progress_and_a_live_edge_stays_zero() -> void:
	var setup := _build_blade(0.2)
	var blade: SkillBlade = setup.blade
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.dead_at[1] = 0.5
	var traj := _traj_member_moves_then_stalls(0.05, 20, 20, Vector2(100.0, 0.0))
	var edge := blade.get_edge_visuals()[0]  # pivot(0) <-> member(1)

	blade._apply_playback_frame(0.3, traj, [], true)
	assert_eq(edge.death_progress(), 0.0, "neither endpoint dead yet")

	blade._apply_playback_frame(0.6, traj, [], true)
	assert_almost_eq(edge.death_progress(), 0.5, 0.01,
			"the edge reads its dead endpoint's own progress")
	assert_false(edge.is_disabled(), "is_disabled() no longer answers endpoint death (#787)")


# ── Acceptance 3: scrub-safety ───────────────────────────────────────────────

func test_scrub_backward_then_forward_reproduces_identical_state() -> void:
	var setup := _build_blade(0.15)
	var blade: SkillBlade = setup.blade
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.dead_at[1] = 0.3
	var traj := _traj_member_moves_then_stalls(0.05, 20, 20, Vector2(100.0, 0.0))
	var visuals := blade.get_node_visuals()
	var edge := blade.get_edge_visuals()[0]

	blade._apply_playback_frame(0.6, traj, [], true)
	var node_progress_1 := visuals[1].death_progress
	var edge_progress_1 := edge.death_progress()
	assert_gt(node_progress_1, 0.0, "fixture sanity: the member should be mid-death by t=0.6")

	blade._apply_playback_frame(0.1, traj, [], true)  # t0 < dead_at, before the pop
	assert_eq(visuals[1].death_progress, 0.0, "rewound before dead_at: back to 0")

	blade._apply_playback_frame(0.6, traj, [], true)  # t1 again
	assert_eq(visuals[1].death_progress, node_progress_1,
			"replay at the same t must reproduce the same death_progress")
	assert_eq(edge.death_progress(), edge_progress_1,
			"...and the same edge progress")


# ── Acceptance 4: seed velocity from the last MOVING sample pair ────────────

func test_seed_velocity_reads_the_last_moving_pair_before_death() -> void:
	var dt := 0.1
	var vel := Vector2(120.0, -40.0)
	# 3 moving steps then 3 stalled ones; "death" lands inside the stalled tail.
	var traj := _traj_member_moves_then_stalls(dt, 3, 3, vel)

	var got := SkillBlade.seed_velocity(traj, 1, 0.4)  # sample index 4, already stalled
	assert_almost_eq(got.x, vel.x, 0.01, "must walk back past the stalled tail")
	assert_almost_eq(got.y, vel.y, 0.01)


func test_seed_velocity_at_t_zero_is_zero() -> void:
	var traj := _traj_member_moves_then_stalls(0.1, 3, 3, Vector2(50.0, 0.0))
	var got := SkillBlade.seed_velocity(traj, 1, 0.0)
	assert_eq(got, Vector2.ZERO, "nothing to diff against at the very start")


# ── Acceptance 5: shard spawn exactly once per pop, zero when ghostly ───────

func test_shard_spawns_exactly_once_across_a_full_forward_playback() -> void:
	var setup := _build_blade(0.1)
	var blade: SkillBlade = setup.blade
	var style: BladeStyle = blade.style
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.dead_at[1] = 0.4
	# Normally [method SkillBlade.play] does this; the tests below drive
	# [method SkillBlade._apply_playback_frame] directly for precise frame
	# control, so the pending-spawn queue is primed by hand the same way.
	blade._rebuild_pending_pops()
	var traj := _traj_member_moves_then_stalls(0.05, 20, 20, Vector2(100.0, 0.0))
	var field := blade.get_shard_field()
	assert_not_null(field, "SkillBlade must mount its own ShatterField")

	var t := 0.0
	while t <= traj.duration():
		blade._apply_playback_frame(t, traj, [], false)
		t += 0.05

	assert_eq(field.used_slots(), style.pop_shard_count,
			"exactly one shatter's worth of shards across the whole forward pass")


func test_ghostly_playback_spawns_no_shards() -> void:
	var setup := _build_blade(0.1)
	var blade: SkillBlade = setup.blade
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.dead_at[1] = 0.4
	blade._rebuild_pending_pops()
	var traj := _traj_member_moves_then_stalls(0.05, 20, 20, Vector2(100.0, 0.0))
	var field := blade.get_shard_field()

	var t := 0.0
	while t <= traj.duration():
		blade._apply_playback_frame(t, traj, [], true)
		t += 0.05

	assert_eq(field.used_slots(), 0, "the ghost drives death_progress but spawns nothing (decision 11)")
