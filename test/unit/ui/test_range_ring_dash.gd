extends GutTest

## RangeRing.dash_spans: the pure dash formula behind a reach circle drawn in
## proportion to a fill fraction (ranged: shots left / max shots). Each of
## `periods` equal periods is lit for `fill` of its arc; fill 1 is one solid
## span, fill 0 draws nothing.

const _EPS := 1e-4


func test_full_fill_is_one_full_span() -> void:
	for p in [1, 5, 12]:
		var spans := RangeRing.dash_spans(1.0, p)
		assert_eq(spans.size(), 1, "fill 1 → one span at periods %d" % p)
		assert_almost_eq(spans[0].x, 0.0, _EPS)
		assert_almost_eq(spans[0].y, TAU, _EPS)


func test_zero_fill_draws_nothing() -> void:
	for p in [1, 5, 12]:
		assert_eq(RangeRing.dash_spans(0.0, p).size(), 0, "fill 0 → empty at periods %d" % p)


func test_partial_fill_lights_each_period_in_proportion() -> void:
	for f in [0.2, 0.5, 0.8]:
		for p in [1, 5, 12]:
			var spans := RangeRing.dash_spans(f, p)
			var tag := "fill %.1f periods %d" % [f, p]
			assert_eq(spans.size(), p, tag + ": one span per period")
			var lit := 0.0
			for i in spans.size():
				assert_almost_eq(spans[i].y - spans[i].x, TAU * f / p, _EPS, tag + ": span length")
				assert_almost_eq(spans[i].x, TAU * i / p, _EPS, tag + ": span start")
				lit += spans[i].y - spans[i].x
			assert_almost_eq(lit, TAU * f, _EPS, tag + ": total lit arc")
