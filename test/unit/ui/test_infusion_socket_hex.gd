extends GutTest

## InfusionSocket.perimeter_run: the filled socket's points/held progress is a
## run along its frame polygon, starting at the top edge's midpoint and going
## clockwise, covering that fraction of the perimeter.

const _EPS := 0.001


func _square() -> PackedVector2Array:
	# Axis-aligned, side 2, centred on the origin; clockwise on screen (y down).
	return PackedVector2Array([Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)])


func _length(run: PackedVector2Array) -> float:
	var total := 0.0
	for i in run.size() - 1:
		total += run[i].distance_to(run[i + 1])
	return total


func test_starts_at_the_top_edge_midpoint() -> void:
	var run := InfusionSocket.perimeter_run(_square(), 0.25)
	assert_almost_eq(run[0], Vector2(0, -1), Vector2.ONE * _EPS)


func test_half_ends_opposite_and_covers_half_the_perimeter() -> void:
	var run := InfusionSocket.perimeter_run(_square(), 0.5)
	assert_almost_eq(run[run.size() - 1], Vector2(0, 1), Vector2.ONE * _EPS)
	assert_almost_eq(_length(run), 4.0, _EPS)


func test_goes_clockwise_on_screen() -> void:
	var run := InfusionSocket.perimeter_run(_square(), 0.125)
	assert_almost_eq(run[run.size() - 1], Vector2(1, -1), Vector2.ONE * _EPS, "first stop is the top-right corner")


func test_full_closes_the_loop() -> void:
	var run := InfusionSocket.perimeter_run(_square(), 1.0)
	assert_almost_eq(_length(run), 8.0, _EPS)
	assert_almost_eq(run[run.size() - 1], run[0], Vector2.ONE * _EPS)


func test_zero_is_empty() -> void:
	assert_eq(InfusionSocket.perimeter_run(_square(), 0.0).size(), 0)
