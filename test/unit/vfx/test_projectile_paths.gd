extends GutTest

## #670 P3/P4 + the [ProjectilePath] ease knob.
##
## Three claims are pinned here, and they are the ones the rest of the spell
## book leans on:
##   1. [WavePath] and [JitterPath] are PURE — same `t`, same point, every call.
##   2. The ease knob defaults to the exact identity, so nothing already shipped
##      moved when it landed.
##   3. Ease remaps TIME, never SHAPE — endpoints stay pinned, so a coordinator's
##      impact-on-the-beat alignment survives any pacing curve.

const ORIGIN := Vector2(100.0, 200.0)
const TARGET := Vector2(700.0, 260.0)

const EXISTING_PATHS: Array[String] = [
	"res://ui/vfx/projectile/path/linear_path.gd",
	"res://ui/vfx/projectile/path/bezier_arc_path.gd",
	"res://ui/vfx/projectile/path/self_loop_path.gd",
	"res://ui/vfx/projectile/path/cubic_bezier_path.gd",
	"res://ui/vfx/projectile/path/curve2d_path.gd",
]

const SAMPLES: Array[float] = [0.0, 0.13, 0.25, 0.5, 0.66, 0.87, 1.0]


# ------------------------------------------------------------------ P3 WavePath


func test_wave_path_is_pure() -> void:
	var path := WavePath.new()
	for t in SAMPLES:
		assert_eq(path.evaluate(t, ORIGIN, TARGET), path.evaluate(t, ORIGIN, TARGET),
			"WavePath must be a pure function of t (t=%s)" % t)


func test_wave_path_pins_both_endpoints() -> void:
	var path := WavePath.new()
	path.frequency = 1.75  # deliberately fractional — sin(TAU*f) is NOT 0 here
	assert_almost_eq(path.evaluate(0.0, ORIGIN, TARGET).distance_to(ORIGIN), 0.0, 0.001,
		"a wave must leave from the origin node")
	assert_almost_eq(path.evaluate(1.0, ORIGIN, TARGET).distance_to(TARGET), 0.0, 0.01,
		"and land on the target node, whatever the frequency")


func test_wave_path_actually_waves() -> void:
	var path := WavePath.new()
	path.amplitude = 40.0
	path.decay = 0.0
	var straight := ORIGIN.lerp(TARGET, 0.25)
	assert_gt(path.evaluate(0.25, ORIGIN, TARGET).distance_to(straight), 1.0,
		"a wave leaves the straight line it is drawn along")


func test_wave_amplitude_zero_is_a_straight_lerp() -> void:
	var path := WavePath.new()
	path.amplitude = 0.0
	for t in SAMPLES:
		assert_almost_eq(path.evaluate(t, ORIGIN, TARGET).distance_to(ORIGIN.lerp(TARGET, t)),
			0.0, 0.001, "amplitude 0 must collapse onto LinearPath (t=%s)" % t)


func test_wave_path_survives_a_degenerate_segment() -> void:
	var path := WavePath.new()
	assert_eq(path.evaluate(0.5, ORIGIN, ORIGIN), ORIGIN,
		"origin == target has no perpendicular; fall through rather than normalise zero")


func test_wave_decay_narrows_toward_the_target() -> void:
	var wide := WavePath.new()
	wide.decay = 0.0
	var settling := WavePath.new()
	settling.decay = 1.0
	settling.frequency = wide.frequency
	settling.amplitude = wide.amplitude
	var line := ORIGIN.lerp(TARGET, 0.75)
	assert_lt(settling.evaluate(0.75, ORIGIN, TARGET).distance_to(line),
		wide.evaluate(0.75, ORIGIN, TARGET).distance_to(line),
		"decay 1.0 must be closer to the straight line late in the flight")


# ---------------------------------------------------------------- P4 JitterPath


func test_jitter_path_is_pure_for_one_instance() -> void:
	# The seed is arbitrary (see the class docs — no peer reproduces a wiggle),
	# but once resolved it is FIXED, so a shared path resource cannot drift
	# between two visuals reading it.
	var path := JitterPath.new()
	for t in SAMPLES:
		assert_eq(path.evaluate(t, ORIGIN, TARGET), path.evaluate(t, ORIGIN, TARGET),
			"JitterPath must be a pure function of t (t=%s)" % t)


func test_an_explicit_seed_reproduces_exactly() -> void:
	var a := JitterPath.new()
	var b := JitterPath.new()
	a.seed_source = 12345
	b.seed_source = 12345
	for t in SAMPLES:
		assert_eq(a.evaluate(t, ORIGIN, TARGET), b.evaluate(t, ORIGIN, TARGET),
			"the same seed_source must give the same path (t=%s)" % t)


func test_different_seeds_give_different_paths() -> void:
	var a := JitterPath.new()
	var b := JitterPath.new()
	a.seed_source = 1
	b.seed_source = 999
	var differs := false
	for t in SAMPLES:
		if a.evaluate(t, ORIGIN, TARGET) != b.evaluate(t, ORIGIN, TARGET):
			differs = true
	assert_true(differs, "two seeds must not collapse onto one squiggle")


func test_jitter_stays_within_its_amplitude() -> void:
	var path := JitterPath.new()
	path.amplitude = 20.0
	path.settle = 0.0
	for i in 101:
		var t: float = float(i) / 100.0
		var offset: float = path.evaluate(t, ORIGIN, TARGET).distance_to(ORIGIN.lerp(TARGET, t))
		assert_lte(offset, path.amplitude + 0.001, "jitter must respect its amplitude (t=%s)" % t)


func test_jitter_leaves_the_line_at_all() -> void:
	var path := JitterPath.new()
	path.amplitude = 20.0
	path.settle = 0.0
	var moved := false
	for i in 40:
		var t: float = float(i) / 40.0
		if path.evaluate(t, ORIGIN, TARGET).distance_to(ORIGIN.lerp(TARGET, t)) > 1.0:
			moved = true
	assert_true(moved, "a jitter path that never leaves the line is a LinearPath")


func test_jitter_amplitude_zero_is_a_straight_lerp() -> void:
	var path := JitterPath.new()
	path.amplitude = 0.0
	for t in SAMPLES:
		assert_almost_eq(path.evaluate(t, ORIGIN, TARGET).distance_to(ORIGIN.lerp(TARGET, t)),
			0.0, 0.001, "amplitude 0 must collapse onto LinearPath (t=%s)" % t)


func test_jitter_path_survives_a_degenerate_segment() -> void:
	assert_eq(JitterPath.new().evaluate(0.5, ORIGIN, ORIGIN), ORIGIN)


# ------------------------------------------------------------------- ease knob


func test_ease_defaults_to_linear() -> void:
	var path := LinearPath.new()
	assert_eq(path.ease_curve, ProjectilePath.Ease.LINEAR, "the default must be linear")
	for t in SAMPLES:
		assert_eq(path.eased(t), t, "linear must be the exact identity (t=%s)" % t)


func test_the_five_existing_paths_are_unchanged_at_default() -> void:
	# The acceptance claim: adding the knob moved nothing already shipped. At
	# the default, `evaluate(t)` must equal what the same path returned before
	# the knob existed — i.e. the un-eased `t`.
	for script_path in EXISTING_PATHS:
		var script: GDScript = load(script_path)
		var path: ProjectilePath = script.new()
		assert_eq(path.ease_curve, ProjectilePath.Ease.LINEAR, "%s defaults linear" % script_path)
		for t in SAMPLES:
			assert_eq(path.eased(t), t, "%s at default must not remap t=%s" % [script_path, t])


func test_zero_strength_is_the_identity_whatever_the_curve() -> void:
	var path := LinearPath.new()
	path.ease_strength = 0.0
	for curve in [ProjectilePath.Ease.IN, ProjectilePath.Ease.OUT,
			ProjectilePath.Ease.IN_OUT, ProjectilePath.Ease.OUT_IN]:
		path.ease_curve = curve
		for t in SAMPLES:
			assert_eq(path.eased(t), t, "strength 0 must be the identity (curve=%s)" % curve)


func test_every_curve_pins_both_endpoints() -> void:
	# Ease remaps TIME, not SHAPE. If a curve moved t=0 or t=1 it would move the
	# projectile's launch or impact point, and the coordinator's beat alignment
	# with it.
	var path := LinearPath.new()
	for curve in [ProjectilePath.Ease.IN, ProjectilePath.Ease.OUT,
			ProjectilePath.Ease.IN_OUT, ProjectilePath.Ease.OUT_IN]:
		path.ease_curve = curve
		assert_almost_eq(path.eased(0.0), 0.0, 0.0001, "curve %s must start at 0" % curve)
		assert_almost_eq(path.eased(1.0), 1.0, 0.0001, "curve %s must end at 1" % curve)


func test_every_curve_is_monotonic() -> void:
	# A projectile never travels backwards.
	var path := LinearPath.new()
	for curve in [ProjectilePath.Ease.IN, ProjectilePath.Ease.OUT,
			ProjectilePath.Ease.IN_OUT, ProjectilePath.Ease.OUT_IN]:
		path.ease_curve = curve
		var previous: float = -1.0
		for i in 101:
			var value: float = path.eased(float(i) / 100.0)
			assert_gte(value, previous - 0.0001, "curve %s went backwards at %s" % [curve, i])
			previous = value


func test_ease_in_starts_slow_and_ease_out_starts_fast() -> void:
	var path := LinearPath.new()
	path.ease_curve = ProjectilePath.Ease.IN
	assert_lt(path.eased(0.25), 0.25, "IN lags early")
	path.ease_curve = ProjectilePath.Ease.OUT
	assert_gt(path.eased(0.25), 0.25, "OUT leads early")


func test_ease_actually_changes_where_a_path_is_at_mid_flight() -> void:
	var linear := LinearPath.new()
	var snappy := LinearPath.new()
	snappy.ease_curve = ProjectilePath.Ease.OUT
	assert_gt(snappy.evaluate(0.25, ORIGIN, TARGET).distance_to(ORIGIN),
		linear.evaluate(0.25, ORIGIN, TARGET).distance_to(ORIGIN),
		"an OUT-eased path is further along at a quarter of its flight")


func test_ease_never_moves_a_paths_endpoints() -> void:
	for script_path in EXISTING_PATHS:
		var path: ProjectilePath = (load(script_path) as GDScript).new()
		path.ease_curve = ProjectilePath.Ease.IN_OUT
		var plain: ProjectilePath = (load(script_path) as GDScript).new()
		for t in [0.0, 1.0]:
			assert_almost_eq(path.evaluate(t, ORIGIN, TARGET).distance_to(
				plain.evaluate(t, ORIGIN, TARGET)), 0.0, 0.01,
				"%s endpoint moved under ease (t=%s)" % [script_path, t])
