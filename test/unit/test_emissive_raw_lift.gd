extends GutTest
## Pins Emissive.raw_lift to the formula both edge views carried before the
## extraction: floor * 2^VALUE + (channel - floor) * 2^stops, alpha untouched.


func _assert_color(got: Color, want: Color) -> void:
	assert_almost_eq(got.r, want.r, 0.0001, "r")
	assert_almost_eq(got.g, want.g, 0.0001, "g")
	assert_almost_eq(got.b, want.b, 0.0001, "b")
	assert_almost_eq(got.a, want.a, 0.0001, "a")


func test_chromatic_base_boosts_only_the_rise_above_the_floor() -> void:
	# floor 0.2 -> 0.4; r: 0.4 + 0.6*4 = 2.8; g: 0.4 + 0.2*4 = 1.2; b: 0.4
	_assert_color(Emissive.raw_lift(Color(0.8, 0.4, 0.2, 0.7), 2.0), Color(2.8, 1.2, 0.4, 0.7))


func test_achromatic_base_gets_only_the_fixed_floor_lift() -> void:
	var lifted := Emissive.raw_lift(Color(0.5, 0.5, 0.5, 1.0), 6.0)
	_assert_color(lifted, Color(1.0, 1.0, 1.0, 1.0))


func test_stops_equal_to_value_is_a_flat_multiply() -> void:
	_assert_color(
		Emissive.raw_lift(Color(0.6, 0.3, 0.1, 0.5), Emissive.VALUE), Color(1.2, 0.6, 0.2, 0.5)
	)
