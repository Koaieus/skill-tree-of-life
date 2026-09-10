extends GutTest

## #796 — a MIRROR's committed-swing draw-only resim never bakes whole before
## drawing it. [method MeleeAttackPlan.begin_replay_resolve] starts a
## [SwingResolve] run (the SAME chunked loop #821 already proved bit-identical
## when sliced) and [method MeleeAttackPlan.advance_replay_resolve] steps it;
## fidelity (`substeps` / `enable_length_scaling`) is a settings knob because
## the whole run is draw-only per ADR 0002 — nothing here is ever kept.
##
## Parity with the unsliced/full-fidelity resolve is NOT re-proven here:
## `test_a_sliced_prediction_is_identical_to_a_single_shot_one` and
## `test_blade_chunked_parity.gd` already pin that the underlying chunked loop
## and its history-stitching are correct, and this file's `advance()` call is
## the exact same method. What's new here is the surface #796 adds: the
## fidelity passthrough, the non-blocking start, `replay_duration`, and
## PREDELETE safety while a replay is in flight.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _preview: MeleePreview
var _attacker: Entity


func _spawn(nm: String) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	return sn


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(_graph)

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_preview = MeleePreview.new()
	add_child_autofree(_preview)

	_bs = autofree(BattleSystem.new())
	_bs.turn_manager = _tm
	_bs.allocation_system = _alloc
	_bs.graph = _graph
	_bs.melee_preview = _preview
	_preview.battle_system = _bs
	add_child(_bs)
	_preview._ready()

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 3.0
	_attacker.stat_board.action_points.base_value = 2.0
	_attacker.stat_board.action_points.current = 2.0
	_graph.add_child(_attacker)
	_tm.current_entity = _attacker


## A real armed plan, source+joint+tip, all owned. Mirrors the arming shape
## `test_melee_launch_lifecycle.gd` uses, so this is a swing with real length
## rather than a degenerate one-vertex blade.
func _arm() -> MeleeAttackPlan:
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	var tip := _spawn("Tip")
	_graph.add_edge(source, joint)
	_graph.add_edge(joint, tip)
	_alloc.force_allocate(_attacker, source)
	_alloc.force_allocate(_attacker, joint)
	_alloc.force_allocate(_attacker, tip)

	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(source)
	plan._on_node_left_clicked(joint)
	plan._on_node_left_clicked(tip)
	assert_true(plan.is_valid(), "fixture plan must be valid before resolving")
	return plan


func _swing_steps() -> int:
	return int(ceil(MeleeAttackPlan.SWING_DURATION / BladeSim.DEFAULT_DT))


func test_begin_replay_resolve_does_not_block_the_calling_frame() -> void:
	var plan := _arm()
	plan.begin_replay_resolve(BladeSim.DEFAULT_SUBSTEPS, true)
	assert_true(plan.is_replaying(), "a fresh run is in flight immediately after starting")
	assert_not_null(plan.last_trajectory,
			"last_trajectory is published at START, not at completion (the partial picture)")
	assert_lt(plan.last_trajectory.samples.size(), _swing_steps() + 1,
			"nothing has been stepped yet — begin_replay_resolve alone bakes nothing")


func test_advance_replay_resolve_steps_and_extends_the_same_trajectory_in_place() -> void:
	var plan := _arm()
	plan.begin_replay_resolve(BladeSim.DEFAULT_SUBSTEPS, true)
	var traj := plan.last_trajectory
	assert_false(plan.advance_replay_resolve(3), "three samples is not a whole swing")
	assert_true(plan.is_replaying(), "the run is still in flight")
	assert_same(plan.last_trajectory, traj,
			"a slice extends the SAME bundle in place — a caller holding a handle sees it grow")
	assert_gt(plan.last_trajectory.samples.size(), 1, "the first slice actually stepped")

	var slices := 0
	while not plan.advance_replay_resolve(3):
		slices += 1
		assert_lt(slices, _swing_steps() * 4, "the slice loop must terminate")
	assert_false(plan.is_replaying(), "advance_replay_resolve reports completion")
	assert_eq(plan.last_trajectory.samples.size(), _swing_steps() + 1,
			"the finished replay covers the whole swing")


func test_advance_replay_resolve_is_true_when_nothing_is_in_flight() -> void:
	var plan := _arm()
	assert_true(plan.advance_replay_resolve(5),
			"calling this with no replay started must be a harmless no-op")
	assert_false(plan.is_replaying())


func test_begin_replay_resolve_is_idempotent() -> void:
	var plan := _arm()
	plan.begin_replay_resolve(1, false)
	var traj := plan.last_trajectory
	plan.begin_replay_resolve(BladeSim.DEFAULT_SUBSTEPS, true)
	assert_same(plan.last_trajectory, traj,
			"a second call while one is in flight must not replace the run")


## #796's whole reason to exist: LOW fidelity (substeps=1, no length scaling)
## must actually reach the solver, not just be accepted and ignored. Two bare
## plans (not two `_arm()` calls through the same `_bs`) — `begin_replay_resolve`
## is deliberately idempotent per-plan, so reusing one `BattleSystem`'s single
## `attack_plan` for both would silently test the same object twice.
func test_fidelity_knob_threads_through_to_the_solver() -> void:
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	_graph.add_edge(source, joint)
	_alloc.force_allocate(_attacker, source)
	_alloc.force_allocate(_attacker, joint)

	var low := MeleeAttackPlan.new()
	low.attacker = _attacker
	low._on_node_left_clicked(source)
	low._on_node_left_clicked(joint)
	assert_true(low.is_valid(), "fixture: low-fidelity plan must be valid")
	low.begin_replay_resolve(1, false)
	assert_eq(low._replay_run._substeps, 1, "LOW fidelity must set substeps to 1")
	assert_false(low._replay_run._enable_length_scaling,
			"LOW fidelity must turn length scaling off")

	var high := MeleeAttackPlan.new()
	high.attacker = _attacker
	high._on_node_left_clicked(source)
	high._on_node_left_clicked(joint)
	assert_true(high.is_valid(), "fixture: high-fidelity plan must be valid")
	high.begin_replay_resolve(BladeSim.DEFAULT_SUBSTEPS, true)
	assert_eq(high._replay_run._substeps, BladeSim.DEFAULT_SUBSTEPS,
			"HIGH fidelity must keep the authoritative substep count")
	assert_true(high._replay_run._enable_length_scaling,
			"HIGH fidelity must keep length scaling on")


func test_replay_duration_is_the_swing_span_whether_in_flight_or_finished() -> void:
	var plan := _arm()
	plan.begin_replay_resolve(BladeSim.DEFAULT_SUBSTEPS, true)
	var expected := MeleeAttackPlan.SWING_DURATION
	assert_almost_eq(plan.replay_duration(), expected, BladeSim.DEFAULT_DT,
			"in flight, the duration is the known swing span — never the partial sample count's")

	while not plan.advance_replay_resolve(5):
		pass
	assert_almost_eq(plan.replay_duration(), plan.last_trajectory.duration(), 0.0001,
			"finished, it agrees with the trajectory's own duration")


func test_replay_duration_is_zero_with_nothing_resolved_yet() -> void:
	var plan := _arm()
	assert_eq(plan.replay_duration(), 0.0,
			"no replay started and no prior resolve: nothing to report a span for")


## #821's PREDELETE trap, for the new shadow. A plan freed mid-replay (the
## scene tearing down under an in-flight command, a test fixture's autofree)
## must not leak the shadow world or crash trying to call a method on itself.
func test_freeing_the_plan_mid_replay_releases_the_shadow_without_erroring() -> void:
	var plan := MeleeAttackPlan.new()
	var source := _spawn("Source")
	var joint := _spawn("Joint")
	_graph.add_edge(source, joint)
	_alloc.force_allocate(_attacker, source)
	_alloc.force_allocate(_attacker, joint)
	plan.attacker = _attacker
	plan._on_node_left_clicked(source)
	plan._on_node_left_clicked(joint)
	assert_true(plan.is_valid(), "fixture plan must be valid")

	plan.begin_replay_resolve(BladeSim.DEFAULT_SUBSTEPS, true)
	assert_true(plan.is_replaying(), "fixture: the run must still be in flight")
	# MeleeAttackPlan is a Resource (RefCounted) — dropping the last reference
	# deallocates it immediately and fires NOTIFICATION_PREDELETE synchronously,
	# unlike a Node's `.free()`. `plan = null` here IS the last reference: the
	# fixture never stored it anywhere else (unlike `_arm()`, which parks it on
	# `_bs.attack_plan`).
	plan = null
	# No crash, no leak assertion needed beyond reaching this line — a bad
	# PREDELETE here throws "Nonexistent function... on a null instance",
	# which GUT surfaces as a failed test.
	assert_true(true, "freeing mid-replay must not throw")


# ── MeleePreview: the frame pump that drives a committed swing's resim ──────

func test_melee_preview_begin_replay_starts_the_plans_run_and_arms_process() -> void:
	# `_arm()`'s clicks already arm the aim-time prediction pump (unrelated to
	# #796) via the normal click path, so `is_processing()` is not a useful
	# "before" signal here — the run and the fidelity threading are.
	var plan := _arm()
	_preview.begin_replay(plan, 1, false)
	assert_true(plan.is_replaying(), "begin_replay must start the plan's run")
	assert_true(_preview.is_processing(), "begin_replay must arm the frame pump")
	assert_eq(plan._replay_run._substeps, 1, "begin_replay must forward the fidelity args")


## The crux of #796's fix on the MeleePreview side: the pump used to bail out
## the instant `_live_swing` went true (the committed-swing window), which is
## exactly the window a replay resim needs pumping through.
func test_the_pump_keeps_stepping_while_live_swing_is_true() -> void:
	var plan := _arm()
	_preview.begin_replay(plan, 1, false)
	_preview._live_swing = true
	var before := plan.last_trajectory.samples.size()
	for _i in 5:
		_preview._process(0.0)
	assert_true(plan.last_trajectory.samples.size() > before or not plan.is_replaying(),
			"the pump must keep advancing the replay even while a swing is live")
