extends GutTest

## FanLayout — the pure rect relaxation solver behind the tooltip fan.
## Fixture: the seven fan panels' pre-bind sizes with compact rests around a
## (0,0) node, the node + HP-band rect and the Roots rect as obstacles. Every
## assertion is on the CONVERGED layout; the step counts are the numbers the
## driver's `settle_seconds` is tuned against.

const _NODE := Rect2(-45.0, -70.0, 90.0, 102.0)
const _ROOTS := Rect2(-60.0, 43.0, 120.0, 160.0)
const _WIDE := Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
const _PADDING := 8.0

## name → [size, rest] (top-left, fan space).
const _SEVEN := {
	"IdChip": [Vector2(75, 45), Vector2(-37, -130)],
	"NodeStats": [Vector2(170, 200), Vector2(60, -100)],
	"Addons": [Vector2(150, 130), Vector2(-210, -100)],
	"Owner": [Vector2(210, 320), Vector2(70, 60)],
	"Core": [Vector2(190, 260), Vector2(-260, 60)],
	"ProcgenDebug": [Vector2(160, 110), Vector2(60, -250)],
	"EffectReadout": [Vector2(230, 180), Vector2(-290, -250)],
}


func _params() -> Dictionary:
	return {"settle_seconds": 0.15, "padding": _PADDING, "relax_iterations": 4}


func _body(size: Vector2, rest: Vector2) -> FanLayout.Body:
	var b := FanLayout.Body.new()
	b.size = size
	b.rest = rest
	b.position = rest
	return b


func _seven() -> Array[FanLayout.Body]:
	var out: Array[FanLayout.Body] = []
	for name: String in _SEVEN:
		out.append(_body(_SEVEN[name][0], _SEVEN[name][1]))
	return out


func _obstacles() -> Array[Rect2]:
	return [_NODE, _ROOTS]


func _rect(b: FanLayout.Body) -> Rect2:
	return Rect2(b.position, b.size)


## Largest axis-aligned gap between two rects (negative when they overlap).
func _gap(a: Rect2, b: Rect2) -> float:
	var gx := maxf(b.position.x - a.end.x, a.position.x - b.end.x)
	var gy := maxf(b.position.y - a.end.y, a.position.y - b.end.y)
	return maxf(gx, gy)


func _assert_layout_clean(bodies: Array[FanLayout.Body], label: String) -> void:
	var names: Array = _SEVEN.keys()
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			assert_false(_rect(bodies[i]).intersects(_rect(bodies[j])),
					"%s: %s and %s intersect (%s vs %s)" % [label, names[i], names[j],
					_rect(bodies[i]), _rect(bodies[j])])
		for o in _obstacles():
			assert_false(_rect(bodies[i]).intersects(o),
					"%s: %s intersects obstacle %s (%s)" % [label, names[i], o, _rect(bodies[i])])


func test_an_unobstructed_body_reaches_its_rest() -> void:
	var b := _body(Vector2(170, 200), Vector2(60, -100))
	b.position = b.rest + Vector2(30, -25)  # a refresh-sized nudge off rest
	var bodies: Array[FanLayout.Body] = [b]
	var steps := FanLayout.settle(bodies, [], _WIDE, _params())
	assert_true(steps >= 0 and steps <= 60, "settled in %d steps (want 0..60)" % steps)
	assert_almost_eq(b.position.x, b.rest.x, 0.05, "x at rest")
	assert_almost_eq(b.position.y, b.rest.y, 0.05, "y at rest")


func test_two_bodies_with_overlapping_rests_end_apart_by_padding() -> void:
	var a := _body(Vector2(150, 130), Vector2(0, 0))
	var b := _body(Vector2(170, 200), Vector2(100, 10))
	var bodies: Array[FanLayout.Body] = [a, b]
	var steps := FanLayout.settle(bodies, [], _WIDE, _params())
	assert_true(steps >= 0, "settled (steps=%d)" % steps)
	var ra := _rect(a)
	var rb := _rect(b)
	assert_gte(_gap(ra.grow(_PADDING * 0.5), rb.grow(_PADDING * 0.5)), 0.0,
			"inflated rects apart: %s vs %s" % [ra, rb])
	assert_gte(_gap(ra, rb), _PADDING - 0.1, "raw gap >= padding: %s vs %s" % [ra, rb])
	assert_lt(a.position.x, b.position.x, "a stays on the left of b")


## The node rect ends at y = 32 and Roots starts at y = 43: an 11 px slot no
## panel fits. A body pushed out of one must not be handed to the other.
func test_no_body_penetrates_an_obstacle_at_convergence() -> void:
	var inside := _body(Vector2(160, 110), Vector2(-40, 80))  # rest inside Roots
	var across := _body(Vector2(160, 110), Vector2(-40, -20))  # rest straddles both
	for b: FanLayout.Body in [inside, across]:
		var bodies: Array[FanLayout.Body] = [b]
		var steps := FanLayout.settle(bodies, _obstacles(), _WIDE, _params())
		assert_true(steps >= 0, "settled (steps=%d) from rest %s" % [steps, b.rest])
		assert_false(_rect(b).intersects(_NODE), "clear of node rect: %s" % _rect(b))
		assert_false(_rect(b).intersects(_ROOTS), "clear of Roots rect: %s" % _rect(b))


## Shallowest push says "left", the wall says "no": the body has to take the
## next-shallowest direction that has room instead of deadlocking on the wall.
func test_a_body_between_an_obstacle_and_a_wall_escapes_the_other_way() -> void:
	var keep_in := Rect2(0, 0, 400, 300)
	var wall_hugger := Rect2(0, 100, 100, 100)
	var b := _body(Vector2(160, 110), Vector2(-100, 110))
	var bodies: Array[FanLayout.Body] = [b]
	var obstacles: Array[Rect2] = [wall_hugger]
	var steps := FanLayout.settle(bodies, obstacles, keep_in, _params())
	assert_true(steps >= 0, "settled (steps=%d)" % steps)
	assert_false(_rect(b).intersects(wall_hugger), "clear of the obstacle: %s" % _rect(b))
	assert_true(keep_in.encloses(_rect(b)), "inside keep_in: %s" % _rect(b))


func test_a_rest_outside_the_window_is_held_inside() -> void:
	var keep_in := Rect2(0, 0, 400, 300)
	var b := _body(Vector2(160, 110), Vector2(350, 260))
	var bodies: Array[FanLayout.Body] = [b]
	var steps := FanLayout.settle(bodies, [], keep_in, _params())
	assert_true(steps >= 0, "settled (steps=%d)" % steps)
	assert_true(keep_in.encloses(_rect(b)), "rect inside keep_in: %s" % _rect(b))


## The mirror of the test above on the RIGHT wall: the clamp parks a body
## exactly on `keep_in.end - size`, and a room test that excludes that edge
## rejects every perpendicular push and falls back to the deadlock direction.
func test_a_body_flush_against_the_right_wall_still_escapes_an_obstacle() -> void:
	var keep_in := Rect2(0, 0, 170, 300)
	var band := Rect2(0, 150, 170, 100)
	var b := _body(Vector2(160, 110), Vector2(10, 160))
	var bodies: Array[FanLayout.Body] = [b]
	var obstacles: Array[Rect2] = [band]
	var steps := FanLayout.settle(bodies, obstacles, keep_in, _params())
	assert_true(steps >= 0, "settled (steps=%d)" % steps)
	assert_false(_rect(b).intersects(band), "clear of the band: %s" % _rect(b))
	assert_true(keep_in.encloses(_rect(b)), "inside keep_in: %s" % _rect(b))


## Two overlapping bodies whose CURRENT order along the shallow axis is the
## opposite of their rest order separate toward rest order (a brief
## pass-through), not into a locked swapped contact.
func test_a_swapped_pair_separates_into_rest_order() -> void:
	var a := _body(Vector2(150, 130), Vector2(0, 0))
	var b := _body(Vector2(150, 130), Vector2(100, 0))
	a.position = Vector2(60, 0)
	b.position = Vector2(40, 0)
	var bodies: Array[FanLayout.Body] = [a, b]
	var steps := FanLayout.settle(bodies, [], _WIDE, _params())
	assert_true(steps >= 0, "settled (steps=%d)" % steps)
	assert_gte(_gap(_rect(a), _rect(b)), _PADDING - 0.1, "apart: %s vs %s" % [_rect(a), _rect(b)])
	assert_lt(a.position.x, b.position.x, "a (rest left) ends left of b: %s vs %s" % [_rect(a), _rect(b)])


func test_the_seven_panel_fan_settles_without_overlap() -> void:
	var bodies := _seven()
	var steps := FanLayout.settle(bodies, _obstacles(), _WIDE, _params())
	assert_true(steps >= 0 and steps <= 120,
			"seven from rests settled in %d steps (want 0..120)" % steps)
	_assert_layout_clean(bodies, "from rests (%d steps)" % steps)


func test_bloom_from_one_point_settles_without_overlap() -> void:
	var bodies := _seven()
	for b in bodies:
		b.position = Vector2(0, -60)
		b.velocity = Vector2.ZERO
	var steps := FanLayout.settle(bodies, _obstacles(), _WIDE, _params())
	assert_true(steps >= 0 and steps <= 120, "bloom settled in %d steps (want 0..120)" % steps)
	_assert_layout_clean(bodies, "bloom (%d steps)" % steps)


func test_step_is_deterministic() -> void:
	var first := _seven()
	var second := _seven()
	for b in first:
		b.position = Vector2(0, -60)
	for b in second:
		b.position = Vector2(0, -60)
	FanLayout.settle(first, _obstacles(), _WIDE, _params())
	FanLayout.settle(second, _obstacles(), _WIDE, _params())
	for i in first.size():
		assert_eq(first[i].position, second[i].position, "body %d identical" % i)
		assert_eq(first[i].velocity, second[i].velocity, "body %d velocity identical" % i)


func test_a_body_larger_than_the_window_pins_to_the_top_left() -> void:
	var keep_in := Rect2(20, 30, 400, 300)
	var b := _body(Vector2(500, 400), Vector2(100, 100))
	var bodies: Array[FanLayout.Body] = [b]
	FanLayout.settle(bodies, [], keep_in, _params())
	assert_eq(b.position, keep_in.position, "pinned to keep_in top-left")
