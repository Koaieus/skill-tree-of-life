extends GutTest

## NoiseField: remaps FastNoiseLite output into [min_value, max_value].


func test_output_stays_within_range() -> void:
	var f := NoiseField.new()
	f.min_value = 0.5
	f.max_value = 1.5
	for i in 50:
		var p := Vector2(i * 17.0, -i * 23.0)
		var v := f.sample(p)
		assert_true(v >= 0.5 and v <= 1.5, "sample %s out of range at %s" % [v, p])


func test_deterministic_for_fixed_seed() -> void:
	var f := NoiseField.new()
	f.noise.seed = 42
	var a := f.sample(Vector2(10, 10))
	var b := f.sample(Vector2(10, 10))
	assert_almost_eq(a, b, 0.0001)


func test_min_equals_max_is_constant() -> void:
	var f := NoiseField.new()
	f.min_value = 1.0
	f.max_value = 1.0
	assert_almost_eq(f.sample(Vector2(5, 5)), 1.0, 0.0001)
	assert_almost_eq(f.sample(Vector2(500, -300)), 1.0, 0.0001)
