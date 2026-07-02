extends GutTest

## Geometry inputs to the strikethrough shader (#84). We don't assert pixels —
## shaders are hard headless — but the diagonal endpoints fed to the shader are
## pure math (StrikethroughToast.strike_endpoints), so we pin THAT: the cut sits
## on the x-height band, tilts the right way, stays in [0,1], and reproduces the
## known-good 0.7/0.4 look for the stock 32px label.

const StrikethroughToast := preload(
		"res://ui/floating_number_layer/strikethrough_toast/strikethrough_toast.gd")

# Stock toast, MEASURED live: "+10 STR" at 32px renders a 119×45 label with
# ascent 35 / total-height 45 (the label's min height, honoured by the toaster
# VBox). These are the real inputs, not invented ones.
const STOCK_ASCENT := 35.0
const STOCK_TOTAL := 45.0
const STOCK_SIZE := Vector2(119, 45)
const RATIO := 0.30
const DEFAULT_ANGLE := 6.5


func test_endpoints_within_unit_range() -> void:
	var e := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, STOCK_SIZE, DEFAULT_ANGLE, RATIO)
	assert_between(e.x, 0.0, 1.0, "split_y_start must be a valid UV")
	assert_between(e.y, 0.0, 1.0, "split_y_end must be a valid UV")


func test_zero_angle_is_flat() -> void:
	# No tilt → both endpoints collapse onto the x-height centreline.
	var e := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, STOCK_SIZE, 0.0, RATIO)
	assert_almost_eq(e.x, e.y, 0.0001, "angle 0 → start == end (a flat strike)")


func test_positive_angle_slopes_bottom_left_to_top_right() -> void:
	# start_y > end_y means the line rises left→right (y is down in UV).
	var e := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, STOCK_SIZE, DEFAULT_ANGLE, RATIO)
	assert_gt(e.x, e.y, "start_y should exceed end_y for a positive tilt")


func test_symmetric_about_x_height_centre() -> void:
	var flat := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, STOCK_SIZE, 0.0, RATIO)
	var tilted := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, STOCK_SIZE, 4.0, RATIO)
	var centre := flat.x  # flat endpoints both sit on the centreline
	assert_almost_eq((tilted.x + tilted.y) * 0.5, centre, 0.0001,
		"the tilt is symmetric about the x-height centreline")


func test_centre_sits_in_x_height_band() -> void:
	# baseline = (45-45)/2 + 35 = 35; cut = 35 - 35*0.30 = 24.5px → 0.544 UV.
	var flat := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, STOCK_SIZE, 0.0, RATIO)
	assert_almost_eq(flat.x, 0.544, 0.01, "cut centre lands in the x-height band")


func test_stock_shape_reproduces_known_good_look() -> void:
	# The default 6.5° at the REAL stock label lands near the old hardcoded
	# 0.7 / 0.4 endpoints that looked right — proof the generalisation matches
	# reality (this is what the earlier H=32 calibration got wrong).
	var e := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, STOCK_SIZE, DEFAULT_ANGLE, RATIO)
	assert_almost_eq(e.x, 0.70, 0.03, "start_y near the good-looking 0.7")
	assert_almost_eq(e.y, 0.39, 0.03, "end_y near the good-looking 0.4")


func test_angle_is_aspect_corrected() -> void:
	# A wider label at the same angle spreads more in UV-y (constant visual angle),
	# so a 2x-wider box yields ~2x the half-spread.
	var narrow := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, Vector2(119, 45), 4.0, RATIO)
	var wide := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, Vector2(238, 45), 4.0, RATIO)
	var narrow_half := (narrow.x - narrow.y) * 0.5
	var wide_half := (wide.x - wide.y) * 0.5
	assert_almost_eq(wide_half, narrow_half * 2.0, 0.01, "half-spread scales with width")


func test_degenerate_height_is_safe() -> void:
	# A not-yet-laid-out label (0 height) must not divide by zero.
	var e := StrikethroughToast.strike_endpoints(STOCK_ASCENT, STOCK_TOTAL, Vector2(119, 0), DEFAULT_ANGLE, RATIO)
	assert_eq(e, Vector2(0.5, 0.5), "0-height falls back to a safe centre")
