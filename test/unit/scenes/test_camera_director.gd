extends GutTest

## #523 — the camera director's arbitration seam.
##
## Every policy assertion here runs against [method CameraDirector.decide],
## which is pure over a [CameraContext] of plain values. That is deliberate and
## is the issue's own hard gate: GUT is headless, easing is not assertable in
## pixels, and a test that asserts what the director *requested* rather than
## where the camera ENDS UP passes while the feature is broken — the pan clamp
## runs regardless of who asked for the move. So the fit/clamp assertions below
## are written against [method FocusDecision.resulting_rect].

const VIEWPORT := Vector2(1440, 960)

var _dir: CameraDirector


func before_each() -> void:
	# No camera, no tree, no frames — `decide` needs none of them.
	_dir = CameraDirector.new()


func after_each() -> void:
	_dir.free()


func _ctx(zoom: float = 1.0, center: Vector2 = Vector2.ZERO) -> CameraContext:
	return CameraContext.make(VIEWPORT, zoom, center)


## A span of `size` centred on `at`, as the two opposite corners.
func _span_request(size: Vector2, at: Vector2 = Vector2.ZERO) -> FocusRequest:
	return FocusRequest.span(PackedVector2Array([at - size * 0.5, at + size * 0.5]))


# --- nothing to frame -------------------------------------------------------

func test_empty_request_does_not_act() -> void:
	var decision := _dir.decide(FocusRequest.span(PackedVector2Array()), _ctx())
	assert_false(decision.act, "no points is nothing to look at")
	assert_eq(decision.reason, &"empty")


func test_empty_reason_is_the_builders_to_name() -> void:
	# #524 filters its span through the fog before handing it over, so "there
	# were points but none survived" must read differently from "malformed".
	var req := FocusRequest.span(PackedVector2Array())
	req.empty_reason = &"fogged"
	assert_eq(_dir.decide(req, _ctx()).reason, &"fogged")


func test_null_request_does_not_act() -> void:
	assert_false(_dir.decide(null, _ctx()).act)


# --- the grace window -------------------------------------------------------

func test_manual_input_holds_the_camera_for_the_grace_window() -> void:
	var ctx := _ctx()
	ctx.seconds_since_manual_input = _dir.manual_grace_seconds - 0.1
	var decision := _dir.decide(_span_request(Vector2(4000, 4000), Vector2(9000, 9000)), ctx)
	assert_false(decision.act, "the player's hands are still on it")
	assert_eq(decision.reason, &"grace")


func test_the_grace_window_expires() -> void:
	var ctx := _ctx()
	ctx.seconds_since_manual_input = _dir.manual_grace_seconds + 0.1
	assert_true(_dir.decide(_span_request(Vector2(4000, 4000), Vector2(9000, 9000)), ctx).act)


func test_a_mandatory_request_ignores_the_grace_window() -> void:
	# #459's handover re-points the view because the SEAT changed hands, not
	# because the game wants to show something — it fires unconditionally.
	var ctx := _ctx()
	ctx.seconds_since_manual_input = 0.0
	var decision := _dir.decide(FocusRequest.point(Vector2(5000, 5000), 0.0, true), ctx)
	assert_true(decision.act, "a handover must re-point even mid-pan")
	assert_eq(decision.target, Vector2(5000, 5000))
	assert_eq(decision.duration, 0.0, "and as a hard cut, as it was before #523")


# --- skip if already framed -------------------------------------------------

func test_a_span_already_comfortably_on_screen_is_skipped() -> void:
	var decision := _dir.decide(_span_request(Vector2(200, 150)), _ctx())
	assert_false(decision.act, "no point panning to what you are looking at")
	assert_eq(decision.reason, &"on_screen")


func test_a_span_off_screen_is_framed() -> void:
	var decision := _dir.decide(_span_request(Vector2(200, 150), Vector2(4000, 0)), _ctx())
	assert_true(decision.act)
	assert_eq(decision.target, Vector2(4000, 0))
	assert_eq(decision.zoom_target, 1.0, "it fits at the player's zoom — pan only")


func test_a_span_at_the_view_edge_is_not_counted_as_on_screen() -> void:
	# Just inside the raw view but outside the 15% inset: still worth framing.
	var edge := VIEWPORT.x * 0.5 - 40.0
	var decision := _dir.decide(_span_request(Vector2(60, 60), Vector2(edge, 0)), _ctx())
	assert_true(decision.act, "the inset is what makes 'on screen' mean 'comfortably'")


# --- fit: pan only, step out, or centre of mass -----------------------------

func test_a_base_melee_swing_never_changes_the_zoom() -> void:
	# ~200px across; fitting it would need zoom 4.1, past MAX_ZOOM.
	for zoom in [0.25, 0.5, 1.0, 2.0]:
		var decision := _dir.decide(_span_request(Vector2(200, 200), Vector2(9000, 9000)), _ctx(zoom))
		assert_true(decision.act)
		assert_eq(decision.zoom_target, zoom, "no zoom change at %s" % zoom)
		assert_false(decision.center_of_mass)


func test_a_long_ranged_shot_steps_the_zoom_out_at_the_default_zoom() -> void:
	# A 1000+ range shot is ~1150px with margin; 960px of visible height at
	# zoom 1.0 does not hold it, so this fires at ORDINARY zoom — the auto-zoom
	# is not a rare rescue for a zoomed-in player.
	var decision := _dir.decide(_span_request(Vector2(1000, 1000), Vector2(9000, 9000)), _ctx(1.0))
	assert_true(decision.act)
	assert_lt(decision.zoom_target, 1.0, "stepped out")
	assert_eq(fmod(decision.zoom_target, CameraDirector.ZOOM_LATTICE), 0.0,
			"and landed on the 0.25 lattice, so the player's wheel survives")
	assert_true(decision.fit_size.y <= VIEWPORT.y / decision.zoom_target, "and it fits now")
	assert_false(decision.center_of_mass)


func test_it_steps_out_only_as_far_as_it_must() -> void:
	var decision := _dir.decide(_span_request(Vector2(1000, 1000), Vector2(9000, 9000)), _ctx(2.0))
	var one_step_in: float = decision.zoom_target + CameraDirector.ZOOM_LATTICE
	assert_gt(decision.fit_size.y, VIEWPORT.y / one_step_in,
			"one lattice step further in would not have fitted")


func test_it_never_zooms_in() -> void:
	# A tiny span at a wide zoom must not be "helpfully" zoomed toward.
	var decision := _dir.decide(_span_request(Vector2(120, 120), Vector2(9000, 9000)), _ctx(0.25))
	assert_eq(decision.zoom_target, 0.25, "the player chose this zoom-out")


func test_a_span_that_cannot_fit_falls_back_to_the_centre_of_mass() -> void:
	# A 20-hop melee blade, ~4400px across: 3840px of visible height at zoom
	# 0.25 cannot hold it. Not an error — centre on the dense part and let the
	# edges fall off screen.
	var points := PackedVector2Array([Vector2(-2200, -2200), Vector2(2200, 2200)])
	# Weight the mass toward one end, so centroid and AABB midpoint differ.
	for i in 8:
		points.append(Vector2(1800 + i, 1800 + i))
	var decision := _dir.decide(FocusRequest.span(points), _ctx(0.25))
	assert_true(decision.act)
	assert_true(decision.center_of_mass, "the span does not fit even at the floor")
	assert_eq(decision.zoom_target, 0.25)
	assert_gt(decision.target.x, 0.0,
			"the centroid follows the mass; the AABB midpoint would sit at 0 in empty space")


func test_the_lattice_floor_sits_above_an_off_lattice_min_zoom() -> void:
	# A small level's floor is an arbitrary float. The director may not go
	# below the nearest lattice value AT OR ABOVE it — the lattice is what
	# lets the player's exact zoom be restored (#524 amendment 2).
	var ctx := _ctx(1.0)
	ctx.min_zoom_floor = 0.63
	var decision := _dir.decide(_span_request(Vector2(9000, 9000), Vector2(0, 0)), ctx)
	assert_eq(decision.zoom_target, 0.75, "0.63 rounds UP to the lattice, not down")
	assert_true(decision.center_of_mass, "and so the fallback fires earlier — intended")


# --- the clamp --------------------------------------------------------------

func test_an_unbounded_context_does_not_clamp() -> void:
	# Mirrors `_update_limits`'s early return. Without it a headless test would
	# clamp against Camera2D's default limits and pass vacuously.
	var decision := _dir.decide(_span_request(Vector2(200, 200), Vector2(50000, 50000)), _ctx())
	assert_false(decision.clamped)
	assert_eq(decision.target, Vector2(50000, 50000))


func test_a_span_in_the_corner_reports_the_clamped_fallback() -> void:
	var ctx := _ctx(1.0)
	ctx.graph_bounds = Rect2(-3000, -2250, 6000, 4500)
	ctx.pan_margin_base = 400.0
	# A span pinned against the far corner of the level.
	var decision := _dir.decide(_span_request(Vector2(200, 200), Vector2(2950, 2200)), ctx)
	assert_true(decision.act)
	assert_true(decision.clamped, "the pan limit pulled it back, and it says so")
	# The gate that matters: assert the RESULTING rect, not the request.
	var shown := decision.resulting_rect(VIEWPORT)
	var span := Rect2(Vector2(2950, 2200) - Vector2(100, 100), Vector2(200, 200))
	assert_true(shown.encloses(span),
			"the span is still on screen after the clamp: %s vs %s" % [shown, span])


func test_the_clamp_centres_when_the_view_is_wider_than_the_level() -> void:
	# The degenerate branch of `_clamp_position` — and the same regime the
	# centre-of-mass fallback lives in, so the clamp can override a centroid.
	var ctx := _ctx(0.25)
	ctx.graph_bounds = Rect2(-500, -400, 1000, 800)
	ctx.pan_margin_base = 100.0
	# Far enough out to clear the skip-if-on-screen inset, so the clamp is what
	# this test is actually exercising.
	var decision := _dir.decide(_span_request(Vector2(200, 200), Vector2(2500, 1600)), ctx)
	assert_true(decision.act)
	assert_eq(decision.target, Vector2.ZERO,
			"a camera cannot centre inside a box smaller than what it shows — it centres the box")


# --- the request's own arithmetic ------------------------------------------

func test_centre_of_mass_is_not_the_aabb_midpoint() -> void:
	var req := FocusRequest.span(PackedVector2Array([
		Vector2(-1000, 0), Vector2(1000, 0), Vector2(900, 0), Vector2(950, 0),
	]))
	assert_eq(req.bounds().get_center(), Vector2(0, 0))
	assert_almost_eq(req.center_of_mass().x, 462.5, 0.01)


func test_a_point_request_never_considers_a_zoom_change() -> void:
	var req := FocusRequest.point(Vector2(9000, 9000))
	assert_false(req.allow_zoom_out)
	assert_eq(_dir.decide(req, _ctx(2.0)).zoom_target, 2.0)


# --- the scene wiring -------------------------------------------------------

## Every assertion above is pure, which leaves the seam's other half — the
## `@export` NodePaths in `game_root.tscn` and the `_ready` connects — with no
## cover at all. A wrong path there is silently null and the whole feature is
## dead while this file stays green.
func test_the_director_is_mounted_and_wired_in_game_root() -> void:
	var root: GameRoot = preload("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	await wait_frames(2)
	var director: CameraDirector = root.camera_director
	assert_not_null(director, "%CameraDirector resolves")
	assert_not_null(director.camera, "camera NodePath")
	assert_not_null(director.vision_system, "vision_system NodePath")
	assert_not_null(director.battle_system, "battle_system NodePath")
	assert_true(director.camera.manual_input_received.is_connected(director._on_manual_input),
			"the player's hands can reach the director")
	assert_true(director.battle_system.attack_committed.is_connected(director._on_attack_committed),
			"and a committed attack can too")
	assert_not_null(director.seat_policy, "GameRoot pushed the seat policy after _setup_level")
