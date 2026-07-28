extends GutTest

## Tooltip V2 (#159): FanTrace draws a PCB/45° connector in from an anchor with a
## glowing traveling tip. Geometry delegates to TraceRouter (#217); this scene
## owns the reveal + lifecycle. Key contracts asserted here:
##   - the drawn Line2D matches TraceRouter output at full progress
##   - progress does arc-length reveal (0 = nothing, 1 = whole line, tip tracks)
##   - the LINE keeps CONSTANT color/width across in → settled → out (#215's
##     never-dim-the-settled-state rule)
##   - route params carry the PCB trunk fraction + direction (angle correctness
##     itself is asserted in test_trace_router.gd, the geometry's home)

const _SCENE := preload("res://ui/tooltip_fan/fan_trace.tscn")


func _make() -> FanTrace:
	var trace := _SCENE.instantiate() as FanTrace
	add_child(trace)
	autofree(trace)
	return trace


# --- pure helper: arc-length reveal -----------------------------------------

func test_polyline_at_full_returns_whole_line() -> void:
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(0, -30), Vector2(40, -30)])
	var slice := FanTrace._polyline_at(pts, 1.0)
	assert_eq(slice.points, pts, "t=1 draws every point")
	assert_eq(slice.head, Vector2(40, -30), "head sits at the last point")


func test_polyline_at_zero_is_degenerate_start() -> void:
	var pts := PackedVector2Array([Vector2(5, 5), Vector2(5, -25)])
	var slice := FanTrace._polyline_at(pts, 0.0)
	assert_eq(slice.head, Vector2(5, 5), "t=0 head parks at the start point")


func test_polyline_at_half_lands_on_arc_midpoint() -> void:
	# Two equal 30px legs (total 60): t=0.5 -> exactly the shared corner.
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(0, -30), Vector2(30, -30)])
	var slice := FanTrace._polyline_at(pts, 0.5)
	assert_eq(slice.head, Vector2(0, -30), "half arc length is the corner between two equal legs")
	assert_eq(slice.points.size(), 2, "reveal reached the corner: [start, corner]")


func test_polyline_at_partial_interpolates_within_a_segment() -> void:
	# Single 100px leg: t=0.25 -> a quarter along it.
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(100, 0)])
	var slice := FanTrace._polyline_at(pts, 0.25)
	assert_eq(slice.head, Vector2(25, 0))


# --- geometry: TraceRouter delegation ---------------------------------------

func test_full_progress_line_matches_trace_router_pcb() -> void:
	var trace := _make()
	trace.from_point = Vector2.ZERO
	trace.to_point = Vector2(60, -80)
	trace.bend_start = 0.5
	await get_tree().process_frame
	trace.progress = 1.0
	var expected := TraceRouter.compute_trace_points(
		trace.from_point, trace.to_point, TraceRouter.Style.PCB, trace._router_params())
	assert_eq(trace._trace.points, expected, "settled line is exactly TraceRouter's PCB polyline")


func test_router_params_carry_trunk_fraction_and_direction() -> void:
	var trace := _make()
	trace.bend_start = 0.382
	trace.trunk_dir = Vector2(0, -1)
	await get_tree().process_frame
	var params := trace._router_params()
	assert_almost_eq(params.trunk, 0.382, 0.001, "trunk fraction is bend_start")
	assert_eq(params.trunk_dir, Vector2(0, -1), "trunk_dir passes through to the router")


# --- constant brightness rule -----------------------------------------------

func test_line_color_and_width_are_constant_across_lifecycle() -> void:
	var trace := _make()
	await get_tree().process_frame
	var color_before := trace._trace.default_color
	var width_before := trace._trace.width

	trace.play_in()
	assert_eq(trace._trace.default_color, color_before, "draw-in must not tint the line")
	assert_eq(trace._trace.width, width_before, "draw-in must not fatten the line")

	trace._on_draw_in_finished() # jump to settled
	assert_eq(trace._trace.default_color, color_before, "settled must not dim the line")

	trace.play_out()
	assert_eq(trace._trace.default_color, color_before, "erase must not tint the line")
	assert_eq(trace._trace.width, width_before)


# --- reveal wiring -----------------------------------------------------------

func test_progress_zero_hides_the_tip_at_runtime() -> void:
	var trace := _make()
	await get_tree().process_frame
	trace.progress = 0.0
	assert_false(trace._tip.visible, "nothing drawn -> tip hidden")


func test_progress_full_parks_tip_at_endpoint() -> void:
	var trace := _make()
	trace.from_point = Vector2.ZERO
	trace.to_point = Vector2(0, -120)
	await get_tree().process_frame
	trace.progress = 1.0
	assert_eq(trace._tip.position, Vector2(0, -120), "tip parks at to_point when fully drawn")


# --- lifecycle tweens --------------------------------------------------------

func test_play_in_returns_a_running_tween() -> void:
	var trace := _make()
	await get_tree().process_frame
	var tw := trace.play_in()
	assert_not_null(tw, "play_in returns its Tween for sequencing")
	assert_true(tw.is_valid(), "the draw-in tween is live")


func test_play_out_returns_a_running_tween() -> void:
	var trace := _make()
	await get_tree().process_frame
	var tw := trace.play_out()
	assert_not_null(tw)
	assert_true(tw.is_valid())


func test_idle_pulse_only_touches_the_tip_never_the_line() -> void:
	var trace := _make()
	trace.trace_idle = true
	await get_tree().process_frame
	var color_before := trace._trace.default_color
	var width_before := trace._trace.width
	trace._on_draw_in_finished() # settles + starts idle
	# Let the idle tween run a beat.
	await get_tree().create_timer(0.1).timeout
	assert_eq(trace._trace.default_color, color_before, "idle must never touch the line color")
	assert_eq(trace._trace.width, width_before, "idle must never touch the line width")
