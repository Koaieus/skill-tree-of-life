extends GutTest

## #559 — a committed melee is STAGED: focus the pivot, form the blade, then
## swing. The acceptance is ordering, never wall-clock equality against an
## authored `.tres` value: the wind-up durations are content for the owner to
## tune, so every bound below is read off [PresentationTempo] at runtime.
##
## Fixture is [i]test_melee_swing_characterization.gd[/i]'s — one arm, one
## coincident hostile target, so the swing lands exactly one hit and "the first
## hit" is unambiguous.
##
## [b]Acceptance 4 (the mutation loop is not gated) is not re-asserted here.[/b]
## The proof is the other 370-odd tests in `test/unit/attack/` passing
## unmodified with the wind-up in the path — same hits, same cascade, same
## order. A test that re-derived it would be a worse copy of that.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")

var _graph: Graph
var _alloc: AllocationSystem
var _tm: TurnManager
var _bs: BattleSystem
var _preview: MeleePreview
var _attacker: Entity
var _defender: Entity
var _pivot: SkillNode
var _arm: SkillNode
var _target: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
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
	_attacker.stat_board.blade_size.base_value = 2.0
	_attacker.stat_board.action_points.base_value = 2.0
	_attacker.stat_board.action_points.current = 2.0
	_graph.entities_container.add_child(_attacker)
	_tm.current_entity = _attacker

	_defender = Entity.new()
	_defender.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	var enemy_camp := Faction.new()
	enemy_camp.id = &"staging_enemy"
	_defender.faction = enemy_camp
	_graph.entities_container.add_child(_defender)

	_pivot = _spawn("Pivot", Vector2.ZERO)
	_arm = _spawn("Arm", Vector2(150, 0))
	_graph.add_edge(_pivot, _arm)
	_target = _spawn("Target", Vector2(150, 0))

	await get_tree().process_frame

	_alloc.force_allocate(_attacker, _pivot)
	_alloc.force_allocate(_attacker, _arm)
	_attacker.core_location = _pivot
	_alloc.force_allocate(_defender, _target)
	_defender.core_location = _target

	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


## Arms a valid two-node blade and returns the plan, WITHOUT launching — so a
## test can look at the preview ghost the player would be watching.
func _arm_plan() -> MeleeAttackPlan:
	_bs.request_attack_mode(BattleSystem.AttackMode.MELEE)
	var plan := _bs.attack_plan as MeleeAttackPlan
	plan._on_node_left_clicked(_pivot)
	plan._on_node_left_clicked(_arm)
	assert_true(plan.is_valid(), "fixture plan must be valid before launching")
	return plan


func _await_launch_settle(max_ticks: int = 900) -> int:
	var ticks := 0
	while _bs.is_launching and ticks < max_ticks:
		await get_tree().process_frame
		ticks += 1
	return ticks


## Every wind-up beat authored to 0 — acceptance 5's regression escape hatch.
## A fresh resource rather than a mutated [method PresentationTempo.shared_default],
## which is one cached object shared by every other test in the process.
func _zeroed_tempo() -> PresentationTempo:
	var tempo := PresentationTempo.new()
	tempo.melee_windup_pivot_focus = 0.0
	tempo.melee_windup_form_span = 0.0
	tempo.melee_windup_stamp_time = 0.0
	tempo.melee_windup_glow_ramp = 0.0
	tempo.melee_windup_flare = 0.0
	return tempo


# --- Acceptance 1: the swing begins after the form beat -----------------------

func test_the_first_hit_lands_strictly_after_the_form_beat_ends() -> void:
	# The SHAPE is injected, not read off the authored `.tres` — twice over on
	# purpose. Authored durations are the owner's to tune, so pinning one here
	# would make a tuning pass a test failure; and a form beat STRETCHED past
	# [member PresentationTempo.swing_duration] is what makes this assertion
	# unfalsifiable-by-luck. Without the staging the first hit lands somewhere
	# inside a 1.2 s swing, which is comfortably before the 2.0 s bound below.
	var tempo := _zeroed_tempo()
	tempo.melee_windup_pivot_focus = 0.6
	tempo.melee_windup_form_span = 1.4
	_bs.presentation_tempo = tempo
	var form_beat_end := tempo.melee_windup_lead() + tempo.melee_windup_form_span
	assert_gt(form_beat_end, tempo.swing_duration,
			"the injected form beat must outlast the whole swing, or a hit "
			+ "landing late inside an unstaged swing would satisfy this vacuously")
	assert_gt(PresentationTempo.shared_default().melee_windup_seconds(false), 0.0,
			"and the AUTHORED default must stage a wind-up at all — the shape "
			+ "is the owner's to tune, but zero would silently retire the feature")

	var first_hit_at := [-1.0]
	var started_at := [0]
	var probe := func(_n: SkillNode, _amount: float, _src: Variant) -> void:
		if first_hit_at[0] < 0.0:
			first_hit_at[0] = float(Time.get_ticks_usec() - started_at[0]) / 1000000.0
	Events.skill_node_damaged.connect(probe)

	_arm_plan()
	started_at[0] = Time.get_ticks_usec()
	_bs.launch_attack()
	await _await_launch_settle()
	Events.skill_node_damaged.disconnect(probe)

	assert_gt(first_hit_at[0], 0.0, "the fixture swing must land a hit at all")
	# Measured wall-clock against a LOGICAL boundary, so it needs slop. The form
	# beat runs on a [BeatClock] tree timer, which fires on accumulated frame
	# deltas — landing at 1.9973 s against a 2.0 s bound is quantization, not a
	# staging failure, and a zero-tolerance `assert_gt` here failed intermittently
	# (caught 2026-09-10: it passed under `test:dir` and failed under `test:one`
	# on the same commit).
	#
	# The slop cannot make this vacuous, which is the point of the stretched beat
	# injected above: WITHOUT staging the first hit lands inside a 1.2 s swing —
	# 800 ms below the bound, sixteen times this tolerance. The assertion still
	# fails loudly if the swing stops waiting for the form beat at all.
	var slop := 0.05
	assert_gt(first_hit_at[0], form_beat_end - slop,
			"the swing's first hit must land after the form beat ends "
			+ "(form beat ends at %.3fs, hit landed at %.3fs, slop %.3fs)"
			% [form_beat_end, first_hit_at[0], slop])


func test_a_committed_melee_opens_the_camera_on_the_pivot_alone() -> void:
	var director := CameraDirector.new()
	director.battle_system = _bs
	director.graph = _graph
	add_child_autofree(director)
	var plan := _arm_plan()

	var pivot_focus := director._melee_pivot_focus(_attacker)
	assert_not_null(pivot_focus, "a committed melee opens on its pivot")
	assert_eq(pivot_focus.points.size(), 1, "the pivot alone, not the span")
	assert_eq(pivot_focus.points[0], _pivot.global_position, "and it is the plan's pivot")
	assert_false(pivot_focus.allow_zoom_out, "a point focus has no span to fit")
	assert_almost_eq(pivot_focus.hold, _bs.tempo().melee_windup_lead(), 0.0001,
			"held for exactly the lead beat, so it does not release before the span widens")
	assert_eq(plan.source, _pivot, "fixture sanity: the pivot is what was framed")


func test_a_seated_actor_raises_no_pivot_focus() -> void:
	# Constraint: the pivot FOCUS stays non-local-only. Nobody yanks their own
	# camera on their own turn (#524/#556), and #559 does not change that —
	# only the beat DURATIONS follow the seat, never the camera rule.
	var director := CameraDirector.new()
	director.battle_system = _bs
	director.graph = _graph
	director.seat_policy = SeatPolicy.seat(_attacker.entity_id)
	add_child_autofree(director)
	_arm_plan()

	var outcome := AttackOutcome.new()
	assert_null(director._build_attack_request(outcome, _attacker),
			"a seated actor's commit frames nothing at all")


# --- Acceptance 2: the local path is a handoff, never a re-predict ------------

func test_a_seated_commit_hands_the_ghost_off_without_re_predicting() -> void:
	assert_ne(_attacker.entity_id, 0, "SeatPolicy.seat needs a minted id")
	_bs.seat_policy = SeatPolicy.seat(_attacker.entity_id)
	var plan := _arm_plan()
	await get_tree().process_frame

	var ghost := _preview.current_blade()
	assert_not_null(ghost, "the preview must have a ghost mounted before the commit")
	var runs_before := plan.prediction_runs

	_bs.launch_attack()
	assert_same(ghost, _preview.current_blade(),
			"the live swing takes over the ghost the player was watching, "
			+ "it does not spawn a second blade")
	assert_eq(plan.prediction_runs, runs_before,
			"launch() must not re-run a resolve — the ghost IS the prediction (#782)")

	await _await_launch_settle()
	assert_eq(plan.prediction_runs, runs_before,
			"and it must not have re-predicted anywhere in the swing either")


# --- Acceptance 3 + the record-ready hook -------------------------------------

func test_the_swing_does_not_begin_while_the_record_ready_hook_is_unsatisfied() -> void:
	# The seam #796 drives. Today `await_record_ready()` is a satisfied no-op on
	# every production path (#545 — the record is final before the confirm), so
	# the only way to observe the await point is to hold it open by hand. With
	# the hook held the form beat simply keeps holding: no hit lands, however
	# long the wind-up's own beats have been over for.
	_bs.hold_record()
	watch_signals(Events)
	_arm_plan()
	_bs.launch_attack()

	# Comfortably past the whole authored wind-up at any frame rate this suite
	# runs at — the form beat is a LOOP that holds, not a fixed clip.
	for _i in 400:
		await get_tree().process_frame

	assert_true(_bs.is_launching, "the launch is still in flight, parked on the hook")
	assert_signal_emit_count(Events, "skill_node_damaged", 0,
			"the swing has not begun, so nothing has been hit")

	_bs.release_record()
	await _await_launch_settle()

	assert_false(_bs.is_launching, "releasing the hook lets the swing run to completion")
	assert_signal_emit_count(Events, "skill_node_damaged", 1,
			"and the same single hit lands, unchanged")


func test_the_hook_is_awaited_on_the_seated_path_too() -> void:
	# The specific bug #559's last comment exists to prevent: gating the
	# staging sequence on `seat_policy.seats(actor)` would delete this await
	# point on the machine that is typically the authority.
	_bs.seat_policy = SeatPolicy.seat(_attacker.entity_id)
	_bs.hold_record()
	watch_signals(Events)
	_arm_plan()
	_bs.launch_attack()

	for _i in 60:
		await get_tree().process_frame

	assert_true(_bs.is_launching, "a seated actor parks on the hook exactly as a remote one does")
	assert_signal_emit_count(Events, "skill_node_damaged", 0,
			"zero-length beats are not the same thing as no await point")

	_bs.release_record()
	await _await_launch_settle()
	assert_signal_emit_count(Events, "skill_node_damaged", 1, "then it swings")


# --- Acceptance 5: the escape hatch ------------------------------------------

func test_zeroed_windup_durations_stage_nothing_and_still_land_the_swing() -> void:
	_bs.presentation_tempo = _zeroed_tempo()
	assert_eq(_bs.tempo().melee_windup_seconds(true), 0.0,
			"every beat authored to 0 is a zero-length wind-up, addons or not")

	watch_signals(Events)
	_arm_plan()
	_bs.launch_attack()
	await _await_launch_settle()

	assert_signal_emit_count(Events, "skill_node_damaged", 1,
			"the same single hit the un-staged swing landed")
	assert_lt(_target.get_current_hp(), _target.get_max_hp(),
			"and it really landed on the target")
