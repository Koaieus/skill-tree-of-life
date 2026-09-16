extends GutTest

## #524 — a non-local actor's committed attack frames its from->to span.
##
## Two halves, tested separately because only one of them needs a world:
##   1. [method CameraDirector._build_attack_request] — the seat predicate, the
##      fog gate and the hold, which need real [SkillNode]s and a
##      [VisionSystem] stub.
##   2. [method CameraDirector.decide] — the fit, the lattice zoom-out, the
##      centre-of-mass fallback and the clamp, which are pure and are asserted
##      on the RESULTING visible rect (see `test_camera_director.gd`).

const _SKILL_NODE := preload("res://skill_node/skill_node.tscn")
const VIEWPORT := Vector2(1440, 960)

var _dir: CameraDirector
var _vision: _StubVision
var _holder: Node2D


## A [VisionSystem] with its answers dictated instead of computed — building a
## real fog recompute here would test VisionSystem, not this. Everything is
## SENSED, so a director that reached for `is_sensed` instead of `is_visible`
## would frame the whole board and the fog tests below would go red.
class _StubVision:
	extends VisionSystem
	var visible_nodes: Array = []
	func is_visible(node: SkillNode) -> bool:
		return visible_nodes.has(node)
	func is_sensed(_node: SkillNode) -> bool:
		return true


func before_each() -> void:
	_holder = Node2D.new()
	add_child_autofree(_holder)
	_vision = _StubVision.new()
	_holder.add_child(_vision)
	_dir = CameraDirector.new()
	_dir.vision_system = _vision
	_holder.add_child(_dir)


func _node_at(pos: Vector2, seen: bool = true) -> SkillNode:
	var n: SkillNode = _SKILL_NODE.instantiate()
	_holder.add_child(n)
	n.global_position = pos
	if seen:
		_vision.visible_nodes.append(n)
	return n


func _hit(origin: SkillNode, target: SkillNode, arrival: float = 0.0) -> HitInstance:
	var h := DamageInstance.new()
	h.amount = 1.0
	h.origin = origin
	h.target = target
	# #543: the fixture authors a STRUCTURAL key; the director compiles the
	# schedule and reads its duration. LITERAL cadence, so the key IS the
	# second — the same numbers, now arriving the way production produces them.
	h.structural_key = arrival
	return h


func _outcome(hits: Array[HitInstance]) -> AttackOutcome:
	var o := AttackOutcome.new()
	o.hits = hits
	return o


func _entity(human: bool) -> Entity:
	var e := Entity.new()
	e.is_human_controlled = human
	_holder.add_child(e)
	return e


# --- the trigger ------------------------------------------------------------

func test_a_seated_actors_ranged_attack_is_never_framed() -> void:
	# On a couch `seats()` is true for every human, so a hot-seat partner's
	# shot is the driving player's own shot — auto-focusing it would be the
	# yank #524 forbids. #866 carved MELEE out of this rule and nothing else:
	# with no melee plan live, the seat early-out is exactly as it was.
	_dir.seat_policy = SeatPolicy.couch()
	var hero := _entity(true)
	var hits: Array[HitInstance] = [_hit(_node_at(Vector2.ZERO), _node_at(Vector2(400, 0)))]
	assert_null(_dir._build_attack_request(_outcome(hits), hero))


func test_a_seated_actors_ranged_attack_is_still_unframed_with_a_battle_system() -> void:
	# The same rule, asserted through the live seam rather than through an
	# unwired `battle_system`: a mounted BattleSystem whose plan is not a
	# MeleeAttackPlan must not turn a ranged commit into a director's shot.
	_dir.seat_policy = SeatPolicy.couch()
	_dir.battle_system = _battle_system(null)
	var hero := _entity(true)
	var hits: Array[HitInstance] = [_hit(_node_at(Vector2.ZERO), _node_at(Vector2(400, 0)))]
	assert_null(_dir._build_attack_request(_outcome(hits), hero),
			"ranged/magic keep today's behaviour exactly (#866)")


# --- #866: every melee commit gets the director's shot -----------------------

func test_a_seated_melee_commit_is_framed_like_everyone_elses() -> void:
	# The inversion. Owner call 2026-09-14: a melee commit is a *director's
	# shot* — "take away camera control for the duration of the move" — and it
	# is unified across seated, AI and remote, so the seat predicate no longer
	# reaches the melee branch at all.
	_dir.seat_policy = SeatPolicy.couch()
	var pivot := _node_at(Vector2.ZERO)
	_dir.battle_system = _battle_system(_melee_plan(pivot))
	var hero := _entity(true)
	var hits: Array[HitInstance] = [_hit(pivot, _node_at(Vector2(400, 0)))]
	var req := _dir._build_attack_request(_outcome(hits), hero)
	assert_not_null(req, "your own swing is framed now")
	assert_true(req.mandatory,
			"and mandatorily — a pan you made while aiming must not eat the shot")


func test_the_pivot_pulls_five_times_as_hard_as_any_other_vertex() -> void:
	# The pan target: weighted average of the blade's node positions, pivot
	# weight x5, every other vertex 1. An unweighted centroid of these two
	# points would sit at x=500.
	var others := PackedVector2Array([Vector2(1000, 0)])
	var center := CameraDirector.weighted_blade_center(Vector2.ZERO, others)
	assert_almost_eq(center.x, 1000.0 / 6.0, 0.001,
			"5 parts pivot to 1 part vertex, not a flat mean")
	assert_almost_eq(center.y, 0.0, 0.001)


func test_the_centroid_translates_as_the_blade_sweeps() -> void:
	# The rubber band: "expect blades of 20, 40, 100 in size — a centroid would
	# surely translate, the pivot never moves." Five vertices swinging from one
	# side of the pivot to the other must drag the shot with them.
	var before := PackedVector2Array()
	var after := PackedVector2Array()
	for i in 5:
		before.append(Vector2(-600, i * 10))
		after.append(Vector2(600, i * 10))
	var a := CameraDirector.weighted_blade_center(Vector2.ZERO, before)
	var b := CameraDirector.weighted_blade_center(Vector2.ZERO, after)
	assert_lt(a.x, -100.0, "the shot leans toward where the blade actually is")
	assert_gt(b.x, 100.0, "and follows it across")
	assert_almost_eq(a.x, -b.x, 0.001, "symmetrically about the unmoving pivot")


func test_an_empty_blade_tracks_the_pivot_alone() -> void:
	assert_eq(CameraDirector.weighted_blade_center(Vector2(7, 9), PackedVector2Array()),
			Vector2(7, 9), "no vertices is the pivot, not a divide by zero")


func test_the_track_target_is_the_pivot_when_no_blade_is_mounted() -> void:
	# The live seam, with no MeleePreview wired: the tracking target still
	# resolves to the plan's pivot rather than to the origin.
	var pivot := _node_at(Vector2(1234, -567))
	_dir.battle_system = _battle_system(_melee_plan(pivot))
	assert_eq(_dir.melee_track_target(), Vector2(1234, -567))


# --- #866: the hard input lock ----------------------------------------------

func test_a_committed_melee_locks_the_camera_until_it_releases() -> void:
	_dir.seat_policy = SeatPolicy.couch()
	var cam := _camera()
	var pivot := _node_at(Vector2.ZERO)
	_dir.battle_system = _battle_system(_melee_plan(pivot))
	var hits: Array[HitInstance] = [_hit(pivot, _node_at(Vector2(400, 0)))]

	_dir._on_attack_committed(_outcome(hits), _entity(true))
	assert_true(_dir.is_melee_locked(), "the shot takes camera control for its duration")
	assert_true(cam.is_input_locked(), "and the camera itself is what enforces it")

	_dir._on_manual_input()
	assert_true(_dir.is_focusing(),
			"HARD lock: manual input does not break the shot, it is ignored")

	_dir.release()
	assert_false(_dir.is_melee_locked(), "release is the one door back")
	assert_false(cam.is_input_locked(),
			"and manual input works normally the instant the shot releases")


func test_a_locked_camera_ignores_the_wheel_entirely() -> void:
	var cam := _camera()
	var before := cam.player_zoom_target()
	var fired := []
	cam.manual_input_received.connect(func() -> void: fired.append(1))

	cam.set_input_locked(true)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	cam._unhandled_input(ev)

	assert_eq(cam.player_zoom_target(), before, "the wheel does nothing while locked")
	assert_eq(fired.size(), 0,
			"and the director is never even told — the grace clock must not reset, "
			+ "or the input would cancel the NEXT shot instead of this one")

	cam.set_input_locked(false)
	cam._unhandled_input(ev)
	assert_eq(fired.size(), 1, "the very next input after release is normal")


func _camera() -> GraphCamera:
	var cam := GraphCamera.new()
	_holder.add_child(cam)
	_dir.camera = cam
	return cam


func _melee_plan(pivot: SkillNode) -> MeleeAttackPlan:
	var plan := MeleeAttackPlan.new()
	plan.source = pivot
	return plan


func _battle_system(plan: AttackPlan) -> BattleSystem:
	var bs := BattleSystem.new()
	_holder.add_child(bs)
	bs.attack_plan = plan
	return bs


func test_an_ai_attack_is_framed_on_a_couch() -> void:
	_dir.seat_policy = SeatPolicy.couch()
	var npc := _entity(false)
	var hits: Array[HitInstance] = [_hit(_node_at(Vector2.ZERO), _node_at(Vector2(400, 0)))]
	var req := _dir._build_attack_request(_outcome(hits), npc)
	assert_not_null(req)
	assert_eq(req.points.size(), 2, "origin and target both frame")


func test_a_remote_humans_attack_is_framed_behind_a_wire() -> void:
	# In SEAT mode only the pinned hero is seated, so every other entity — AI
	# *or remote human* — is a non-local actor.
	var mine := _entity(true)
	mine.entity_id = 7
	var theirs := _entity(true)
	theirs.entity_id = 9
	_dir.seat_policy = SeatPolicy.seat(7)
	var hits: Array[HitInstance] = [_hit(_node_at(Vector2.ZERO), _node_at(Vector2(400, 0)))]
	assert_null(_dir._build_attack_request(_outcome(hits), mine), "my own swing")
	assert_not_null(_dir._build_attack_request(_outcome(hits), theirs), "theirs")


func test_an_outcome_with_no_hits_fires_nothing() -> void:
	_dir.seat_policy = SeatPolicy.couch()
	assert_null(_dir._build_attack_request(_outcome([] as Array[HitInstance]), _entity(false)))


# --- the fog gate -----------------------------------------------------------

func test_a_fogged_origin_frames_the_visible_target_alone() -> void:
	_dir.seat_policy = SeatPolicy.couch()
	var origin := _node_at(Vector2(-2000, 0), false)
	var target := _node_at(Vector2(400, 0))
	var hits: Array[HitInstance] = [_hit(origin, target)]
	var req := _dir._build_attack_request(_outcome(hits), _entity(false))
	assert_eq(req.points, PackedVector2Array([Vector2(400, 0)]),
			"is_visible filters BEFORE the AABB is built")


func test_a_fully_fogged_attack_does_not_move_the_camera() -> void:
	_dir.seat_policy = SeatPolicy.couch()
	var hits: Array[HitInstance] = [_hit(_node_at(Vector2.ZERO, false), _node_at(Vector2(400, 0), false))]
	var req := _dir._build_attack_request(_outcome(hits), _entity(false))
	assert_true(req.points.is_empty())
	var decision := _dir.decide(req, CameraContext.make(VIEWPORT, 1.0, Vector2.ZERO))
	assert_false(decision.act, "do not pan to reveal what the player cannot see")
	assert_eq(decision.reason, &"fogged", "and say so — this is not a malformed request")


func test_a_sensed_but_not_visible_node_does_not_count() -> void:
	# The stub reports EVERYTHING sensed. `is_sensed` does not count (#524
	# item 3), so a director reading it instead would frame this attack.
	_dir.seat_policy = SeatPolicy.couch()
	var hits: Array[HitInstance] = [_hit(_node_at(Vector2.ZERO, false), _node_at(Vector2(400, 0), false))]
	var req := _dir._build_attack_request(_outcome(hits), _entity(false))
	assert_true(_vision.is_sensed(hits[0].target), "the stub does sense it")
	assert_true(req.points.is_empty(), "and it is still not framed")


# --- the hold ---------------------------------------------------------------

func test_the_hold_is_the_last_arrival_plus_a_tail() -> void:
	_dir.seat_policy = SeatPolicy.couch()
	var a := _node_at(Vector2.ZERO)
	var hits: Array[HitInstance] = [
		_hit(a, _node_at(Vector2(400, 0)), 0.4),
		_hit(a, _node_at(Vector2(800, 0)), 1.2),
		_hit(a, _node_at(Vector2(600, 0)), 0.9),
	]
	var req := _dir._build_attack_request(_outcome(hits), _entity(false))
	assert_almost_eq(req.hold, 1.2 + _dir.release_tail_seconds, 0.001,
			"sized from OutcomeSchedule.duration() — the director READS the clock, never gates it")


# --- the three fit branches, on a real span --------------------------------

func test_a_base_melee_swing_pans_without_touching_the_zoom() -> void:
	var decision := _decide_for_span(Vector2(9000, 9000), Vector2(9200, 9000), 1.0)
	assert_true(decision.act)
	assert_eq(decision.zoom_target, 1.0)
	assert_false(decision.center_of_mass)


func test_a_long_ranged_shot_steps_out_at_the_default_zoom() -> void:
	var decision := _decide_for_span(Vector2(9000, 9000), Vector2(9000, 10100), 1.0)
	assert_true(decision.act)
	assert_lt(decision.zoom_target, 1.0, "a 1100px span does not fit in 960px of view")
	assert_true(decision.fit_size.y <= VIEWPORT.y / decision.zoom_target)


func test_a_twenty_hop_blade_falls_back_to_the_centre_of_mass() -> void:
	var decision := _decide_for_span(Vector2(9000, 9000), Vector2(9000, 13400), 1.0)
	assert_true(decision.act)
	assert_true(decision.center_of_mass, "4400px exceeds 3840px even at the 0.25 floor")
	assert_eq(decision.zoom_target, 0.25, "and it stopped at the floor rather than erroring")


func _decide_for_span(from: Vector2, to: Vector2, zoom: float) -> FocusDecision:
	_dir.seat_policy = SeatPolicy.couch()
	var hits: Array[HitInstance] = [_hit(_node_at(from), _node_at(to))]
	var req := _dir._build_attack_request(_outcome(hits), _entity(false))
	return _dir.decide(req, CameraContext.make(VIEWPORT, zoom, Vector2.ZERO))


# --- the clamp, on the resulting rect --------------------------------------

func test_an_attack_in_the_map_corner_still_ends_up_on_screen() -> void:
	_dir.seat_policy = SeatPolicy.couch()
	var hits: Array[HitInstance] = [_hit(_node_at(Vector2(2700, 2000)), _node_at(Vector2(2950, 2200)))]
	var req := _dir._build_attack_request(_outcome(hits), _entity(false))
	var ctx := CameraContext.make(VIEWPORT, 1.0, Vector2.ZERO)
	ctx.graph_bounds = Rect2(-3000, -2250, 6000, 4500)
	var decision := _dir.decide(req, ctx)
	assert_true(decision.act)
	# The gate: the RESULTING rect, not the requested target. `_clamp_position`
	# runs regardless of who asked for the move.
	var shown := decision.resulting_rect(VIEWPORT)
	assert_true(shown.encloses(req.bounds()),
			"the span survived the pan clamp: %s vs %s" % [shown, req.bounds()])


# --- #894: centroid tracking waits for the swing; the follow is a spring ------

func _tempo(lead: float, form: float, stamp: float = 0.0, glow: float = 0.0,
		flare: float = 0.0) -> PresentationTempo:
	var t := PresentationTempo.new()
	t.melee_windup_pivot_focus = lead
	t.melee_windup_form_span = form
	t.melee_windup_stamp_time = stamp
	t.melee_windup_glow_ramp = glow
	t.melee_windup_flare = flare
	return t


func test_tracking_is_live_from_commit_and_the_swing_beat_only_marks_the_swing() -> void:
	# Owner, 2026-09-16: "camera still does a 2-step before the movement: first
	# pan towards pivot, then towards centroid ... recalculating the centroid
	# as things get added". So the goalpost is live from the commit — it reads
	# the PLACED vertices, pivot first — and the swing beat only marks the
	# swing (for the hold), it no longer arms anything.
	_dir.seat_policy = SeatPolicy.couch()
	var cam := _camera()
	var pivot := _node_at(Vector2.ZERO)
	_dir.battle_system = _battle_system(_melee_plan(pivot))
	var outcome := _outcome([_hit(pivot, _node_at(Vector2(400, 0)))])

	_dir._on_attack_committed(outcome, _entity(true))
	assert_true(_dir.is_tracking(), "commit: the goalpost is live, on the pivot alone")
	assert_true(cam.is_following(), "and the pivot focus already opened in follow mode")
	_dir._on_melee_swing_started(outcome)
	assert_true(_dir.is_tracking(), "the swing changes nothing about the goalpost")

	_dir.release()
	_dir._on_melee_swing_started(outcome)
	assert_false(_dir.is_tracking(),
			"a swing beat after release cannot re-arm a shot that has ended")


func test_the_widen_changes_the_zoom_without_restarting_the_pan() -> void:
	# The second step of the 2-step: `begin_directed_follow` re-tweens the pan
	# on every call, so the widen yanked the camera off the band's goalpost
	# toward the span centre. While a follow is open, a widen retargets the
	# ZOOM only; the goalpost stays the band's.
	_dir.seat_policy = SeatPolicy.couch()
	var cam := _camera()
	cam.limit_left = -100000
	cam.limit_right = 100000
	cam.limit_top = -100000
	cam.limit_bottom = 100000
	var pivot := _node_at(Vector2.ZERO)
	var bs := _battle_system(_melee_plan(pivot))
	bs.presentation_tempo = _tempo(0.0, 1.0)
	_dir.battle_system = bs
	var hits: Array[HitInstance] = [_hit(pivot, _node_at(Vector2(0, 3000)))]

	_dir._on_attack_committed(_outcome(hits), _entity(true))
	assert_true(cam.is_following(), "no lead beat: the span landed straight into follow mode")
	cam.set_follow_target(Vector2(50, 0))
	_dir.request_focus(_dir._build_attack_request(_outcome(hits), _entity(true)))
	assert_false(cam.is_pan_tween_running(),
			"a widen on an open follow does not start a pan tween")
	assert_lt(cam._target_zoom, 1.0, "...but the span still stepped the zoom out")
	for _i in 30:
		cam._follow(1.0 / 60.0)
	assert_almost_eq(cam.global_position, Vector2(50, 0), Vector2(1.0, 1.0),
			"the band keeps pulling to ITS goalpost, not the span centre")


func test_only_placed_vertices_pull_during_the_form_in() -> void:
	# The centroid grows with the stagger: a vertex the form-in has not placed
	# yet does not pull, so the pan is one continuous band from the pivot to
	# the rest centroid, landing exactly as the last vertex does.
	_dir.seat_policy = SeatPolicy.couch()
	var pivot := _node_at(Vector2.ZERO)
	var far := _node_at(Vector2(0, 600))
	var plan := _melee_plan(pivot)
	plan.blade_nodes = [far]
	var bs := _battle_system(plan)
	var preview := MeleePreview.new()
	_holder.add_child(preview)
	bs.melee_preview = preview
	_dir.battle_system = bs

	preview.begin_windup(plan, _tempo(0.0, 100.0), false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(_dir.melee_track_target(), Vector2.ZERO, Vector2(0.001, 0.001),
			"pivot placed, far vertex still 100s out: only the pivot pulls")

	preview.current_blade().form_instantly()
	var rest := CameraDirector.weighted_blade_center(Vector2.ZERO,
			PackedVector2Array([Vector2(0, 600)]))
	assert_almost_eq(_dir.melee_track_target(), rest, Vector2(0.001, 0.001),
			"every vertex placed: the goalpost IS the rest centroid, no jump at the swing")


func test_a_melee_shot_waits_for_its_swing_however_long_the_windup_holds() -> void:
	# The span's hold is sized from the SWING (schedule.duration() + tail) but
	# opened at the widen beat, so on its own clock it expires mid-wind-up and
	# the swing played with a dead camera. The shot's course is the launch:
	# while the battle system is still launching and no swing has started, the
	# timer does not release it.
	_dir.seat_policy = SeatPolicy.couch()
	_camera()
	var pivot := _node_at(Vector2.ZERO)
	var bs := _battle_system(_melee_plan(pivot))
	bs.presentation_tempo = _tempo(0.0, 5.0)
	_dir.battle_system = bs
	var outcome := _outcome([_hit(pivot, _node_at(Vector2(400, 0)), 0.5)])

	_dir._on_attack_committed(outcome, _entity(true))
	bs.is_launching = true
	_dir._process(1000.0)
	assert_true(_dir.is_melee_locked(), "far past the hold, still launching: the shot waits")

	_dir._on_melee_swing_started(outcome)
	_dir._process(0.01)
	assert_true(_dir.is_melee_locked(), "the swing re-sizes the hold from its own start")
	_dir._process(1000.0)
	assert_false(_dir.is_melee_locked(),
			"after the swing the tail governs — the launch flag no longer holds the camera")


func test_a_melee_shot_with_no_swing_still_releases_once_the_launch_ends() -> void:
	# `_commit` skips the wind-up and the preview when no MeleePreview is wired
	# (a headless peer), so no swing beat ever fires — the guard must lift with
	# `is_launching` or the camera would be locked for good.
	_dir.seat_policy = SeatPolicy.couch()
	_camera()
	var pivot := _node_at(Vector2.ZERO)
	var bs := _battle_system(_melee_plan(pivot))
	_dir.battle_system = bs
	_dir._on_attack_committed(_outcome([_hit(pivot, _node_at(Vector2(400, 0)))]), _entity(true))
	bs.is_launching = false
	_dir._process(1000.0)
	assert_false(_dir.is_melee_locked(), "nothing to wait for: the timer releases as before")


func test_the_swing_beat_does_not_reopen_a_shot_the_widen_already_holds() -> void:
	_dir.seat_policy = SeatPolicy.couch()
	var cam := _camera()
	var pivot := _node_at(Vector2.ZERO)
	var bs := _battle_system(_melee_plan(pivot))
	bs.presentation_tempo = _tempo(0.1, 0.3)
	_dir.battle_system = bs
	var outcome := _outcome([_hit(pivot, _node_at(Vector2(400, 0)))])

	_dir._on_attack_committed(outcome, _entity(true))
	await wait_seconds(0.2)
	assert_true(cam.is_following(), "after the lead the span has widened, still following")
	assert_true(_dir.is_tracking(), "and the band was never interrupted")
	_dir._on_melee_swing_started(outcome)
	assert_true(_dir.is_melee_locked(), "the swing beat only re-sizes the hold")
