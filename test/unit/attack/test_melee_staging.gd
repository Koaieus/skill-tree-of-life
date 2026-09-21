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
	# #982: the staging and mutation beats run on `BeatClock.instant_clock()`
	# — order and authored slots survive, wall-clock waits do not.
	_bs.instant_mutation = true
	add_child(_bs)
	_preview._ready()

	_attacker = Entity.new()
	_attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_attacker.stat_board.blade_size.base_value = 2.0
	_attacker.stat_board.action_points.base_value = 2.0
	_attacker.stat_board.action_points.current = 2.0
	_graph.entities_container.add_child(_attacker)
	_tm.start_turn(_attacker)

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


## Waits until `_bs.is_launching` clears, capped in seconds. The staging and
## mutation beats are instant here (#982), so what this still waits out is the
## live swing: `SkillBlade.play` runs a real `create_tween()` sized off a
## schedule compiled from `shared_default()` (battle_system.gd:899 —
## `OutcomeSchedule.compile(outcome)` without `tempo()`), plus a hardcoded
## 0.45 s fade in `MeleePreview.launch`. Neither reads `instant_mutation`;
## see #982 for the seam. A seconds cap, never a tick count: the headless
## frame period is a test-hook knob and varies between machines.
func _await_launch_settle(max_seconds: float = 5.0) -> void:
	await wait_until(func() -> bool: return not _bs.is_launching, max_seconds)


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
	await _assert_first_hit_lands_after_the_form_beat()


## #865: the seated path runs the SAME sequence — `begin_windup`'s
## `form_instantly(); return 0.0` branch is gone, so acceptance 1's stretched-beat
## assertion must hold identically with the local seat pinned on the attacker.
func test_the_first_hit_lands_after_the_form_beat_on_the_seated_path_too() -> void:
	assert_ne(_attacker.entity_id, 0, "SeatPolicy.seat needs a minted id")
	_bs.seat_policy = SeatPolicy.seat(_attacker.entity_id)
	await _assert_first_hit_lands_after_the_form_beat()


## #865: one tempo shape, shared by seated and incoming swings — the owner
## explicitly refused a second seated set of numbers. A seated commit stages a
## nonzero wind-up of exactly the length an AI/remote commit stages.
func test_a_seated_commit_stages_the_same_nonzero_windup_as_an_incoming_swing() -> void:
	var plan := _arm_plan()
	await get_tree().process_frame
	var tempo := _bs.tempo()
	assert_gt(tempo.melee_windup_seconds(false), 0.0,
			"the authored default must stage a wind-up at all")

	var seated_length := _preview.begin_windup(plan, tempo, true)
	assert_gt(seated_length, 0.0,
			"a seated commit no longer collapses every beat to zero (#865)")
	var incoming_length := _preview.begin_windup(plan, tempo, false)
	assert_almost_eq(seated_length, incoming_length, 0.0001,
			"and it is the SAME shape — no second seated set of durations")


func _assert_first_hit_lands_after_the_form_beat() -> void:
	# The SHAPE is injected, not read off the authored `.tres`: authored
	# durations are the owner's to tune, so pinning one here would make a tuning
	# pass a test failure. Stretched past [member PresentationTempo.swing_duration]
	# so the pure `form_beat_end > swing_duration` guard below stays meaningful
	# for the real-clock keeper this shape is shared with
	# (`test/integration/attack/test_melee_first_hit_after_form_beat.gd`).
	#
	# On the instant clock (#982) this asserts the two halves the clock does
	# not touch: the wind-up the tempo RESOLVES to is exactly the form beat
	# (the formula), and the hit lands in code order after the commit and the
	# swing-start beat (the order). Whether the real clock really waits the
	# form beat out before the swing is the keeper's one assertion, not this
	# file's eleven.
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

	# The formula: with stamp, glow and flare zeroed the whole staged wind-up IS
	# the form beat, read back through `_bs.tempo()` so the injection is proven
	# to have taken — a pure call, never a stopwatch.
	assert_almost_eq(_bs.tempo().melee_windup_seconds(false), form_beat_end, 0.0001,
			"the wind-up the tempo resolves to ends exactly where the form beat ends "
			+ "(lead %.3fs + form %.3fs)" % [tempo.melee_windup_lead(), tempo.melee_windup_form_span])

	# The order: commit → wind-up → swing-start beat → first landing, in code
	# order. An instant clock advances without waiting and keeps exactly this.
	var order: Array[StringName] = []
	var on_committed := func(_o: AttackOutcome, _e: Entity) -> void:
		order.append(&"committed")
	var on_swing := func(_o: AttackOutcome) -> void:
		order.append(&"swing")
	var on_hit := func(_n: SkillNode, _amount: float, _src: Variant) -> void:
		order.append(&"hit")
	_bs.attack_committed.connect(on_committed)
	_bs.melee_swing_started.connect(on_swing)
	Events.skill_node_damaged.connect(on_hit)

	_arm_plan()
	_bs.launch_attack()
	await _await_launch_settle()
	# `Events` is an autoload that outlives this test; the bus hook must go.
	Events.skill_node_damaged.disconnect(on_hit)

	assert_eq(order, [&"committed", &"swing", &"hit"] as Array[StringName],
			"the commit stages the wind-up, the swing-start beat fires when it "
			+ "is over, and only then does the first hit land")
	assert_lt(_target.get_current_hp(), _target.get_max_hp(),
			"and the hit really landed on the target")


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


func test_a_seated_actor_gets_the_same_pivot_focus_as_everyone_else() -> void:
	# INVERTED by #866. #559's constraint 2 ("nobody yanks their own camera")
	# is superseded for melee: the owner's call 2026-09-14 is a unified
	# director's shot on every melee commit, seated included — *"take away
	# camera control for the duration of the move"*. The seat predicate now
	# reaches neither the beat durations (#865) nor the camera (#866).
	var director := CameraDirector.new()
	director.battle_system = _bs
	director.graph = _graph
	director.seat_policy = SeatPolicy.seat(_attacker.entity_id)
	add_child_autofree(director)
	_arm_plan()

	var pivot_focus := director._melee_pivot_focus(_attacker)
	assert_not_null(pivot_focus, "a seated commit opens on its pivot too")
	assert_eq(pivot_focus.points[0], _pivot.global_position)

	# And the span that widens onto it after the lead beat — this is the half
	# the seat early-out used to kill outright.
	var outcome := AttackOutcome.new()
	var hit := DamageInstance.new()
	hit.amount = 1.0
	hit.origin = _pivot
	hit.target = _target
	hit.structural_key = 0.0
	outcome.hits = [hit] as Array[HitInstance]
	assert_not_null(director._build_attack_request(outcome, _attacker),
			"a seated actor's melee commit is framed like anyone else's (#866)")


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

func test_the_swing_start_beat_fires_once_and_before_the_first_hit() -> void:
	# #894: the camera arms its centroid tracking on this beat, so it must fire
	# exactly once per launch and ahead of the first landing hit — a beat that
	# fired after (or never) is the "no camera movement during the swing" the
	# owner saw.
	var order: Array[StringName] = []
	_bs.melee_swing_started.connect(func(_o: AttackOutcome) -> void:
		order.append(&"swing"))
	Events.skill_node_damaged.connect(func(_n: SkillNode, _amt: float, _src: Variant) -> void:
		order.append(&"hit"), CONNECT_ONE_SHOT)
	_arm_plan()
	_bs.launch_attack()
	await _await_launch_settle()
	assert_eq(order, [&"swing", &"hit"] as Array[StringName],
			"one swing beat, then the hit lands")


func test_the_stagger_places_the_pivot_before_the_arm() -> void:
	# #928: "placed" follows the stagger — the pivot pops first, a farther hop
	# waits its delay. This is what lets the camera's goalpost grow with the
	# form-in instead of jumping to the full centroid.
	var tempo := _zeroed_tempo()
	tempo.melee_windup_form_span = 100.0
	var plan := _arm_plan()
	_preview.begin_windup(plan, tempo, false)
	var blade := _preview.current_blade()
	await get_tree().process_frame
	await get_tree().process_frame
	var pivot_idx: int = blade.state.pivot_index
	var arm_idx := 1 - pivot_idx
	assert_true(blade.is_vertex_placed(pivot_idx), "the pivot pops on the lead beat")
	assert_false(blade.is_vertex_placed(arm_idx), "the arm is 100s of stagger away")
	blade.form_instantly()
	assert_true(blade.is_vertex_placed(arm_idx), "a formed blade is fully placed")


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

	# The wind-up is instant here, so `launch_attack()` returned already parked
	# on the hook; a few frames prove the park is a hold, not a fixed clip.
	for _i in 10:
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

	for _i in 10:
		await get_tree().process_frame

	assert_true(_bs.is_launching, "a seated actor parks on the hook exactly as a remote one does")
	assert_signal_emit_count(Events, "skill_node_damaged", 0,
			"the staged beats are not the same thing as the await point — "
			+ "the hook holds the swing however long the wind-up has been over for")

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
