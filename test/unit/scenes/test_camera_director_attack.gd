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

func test_a_seated_actors_attack_is_never_framed() -> void:
	# On a couch `seats()` is true for every human, so a hot-seat partner's
	# swing is the driving player's own swing — auto-focusing it would be the
	# yank the issue forbids.
	_dir.seat_policy = SeatPolicy.couch()
	var hero := _entity(true)
	var hits: Array[HitInstance] = [_hit(_node_at(Vector2.ZERO), _node_at(Vector2(400, 0)))]
	assert_null(_dir._build_attack_request(_outcome(hits), hero))


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
