extends GutTest

## Shared cubic-ease helper (#1005): the endpoints land exactly, and out_cubic
## is monotone across the domain (no overshoot, no plateau).


func test_out_cubic_endpoints() -> void:
	assert_eq(Easing.out_cubic(0.0), 0.0)
	assert_eq(Easing.out_cubic(1.0), 1.0)


func test_out_cubic_monotone() -> void:
	var previous := Easing.out_cubic(0.0)
	var steps := 20
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var value := Easing.out_cubic(t)
		assert_true(value >= previous, "out_cubic should be monotone at t=%s" % t)
		previous = value


func test_in_cubic_endpoints() -> void:
	assert_eq(Easing.in_cubic(0.0), 0.0)
	assert_eq(Easing.in_cubic(1.0), 1.0)


func test_in_out_cubic_endpoints_and_midpoint() -> void:
	assert_eq(Easing.in_out_cubic(0.0), 0.0)
	assert_eq(Easing.in_out_cubic(1.0), 1.0)
	assert_eq(Easing.in_out_cubic(0.5), 0.5)
