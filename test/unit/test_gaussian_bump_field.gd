extends GutTest

## GaussianBumpField: 1.0 baseline + summed Gaussian bumps over `centers`.


func test_no_centers_is_neutral() -> void:
	var f := GaussianBumpField.new()
	assert_almost_eq(f.sample(Vector2(0, 0)), 1.0, 0.0001)
	assert_almost_eq(f.sample(Vector2(999, 999)), 1.0, 0.0001)


func test_peak_at_center_equals_baseline_plus_amplitude() -> void:
	var f := GaussianBumpField.new()
	f.centers = [Vector2.ZERO]
	f.sigma = 50.0
	f.amplitude = 2.0
	assert_almost_eq(f.sample(Vector2.ZERO), 3.0, 0.0001)


func test_decays_with_distance() -> void:
	var f := GaussianBumpField.new()
	f.centers = [Vector2.ZERO]
	f.sigma = 50.0
	f.amplitude = 2.0
	var near := f.sample(Vector2(10, 0))
	var far := f.sample(Vector2(200, 0))
	assert_true(near > far, "near=%s far=%s should decay outward" % [near, far])
	assert_almost_eq(far, 1.0, 0.01)


func test_multiple_centers_sum() -> void:
	var f := GaussianBumpField.new()
	f.centers = [Vector2(-30, 0), Vector2(30, 0)]
	f.sigma = 50.0
	f.amplitude = 1.0
	# Midpoint gets contribution from both bumps, more than either alone.
	var mid := f.sample(Vector2.ZERO)
	var one := GaussianBumpField.new()
	one.centers = [Vector2(-30, 0)]
	one.sigma = 50.0
	one.amplitude = 1.0
	var single := one.sample(Vector2.ZERO)
	assert_true(mid > single, "mid=%s single=%s should sum contributions" % [mid, single])
