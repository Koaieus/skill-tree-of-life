extends GutTest

## The legibility threshold every subdivided gauge answers to (#1047).
##
## [GaugeDensity] is the sole owner of "is this subdivision legible", and what
## it measures is INK, not pitch: the shader leaves `cell_w - cell_gap` of
## visible cell, so a 3px gap turns a 7px pitch into a 4px mark. A gauge binds
## its `subdivisions` (a model count — skill points, AP) and the gauge itself
## resolves that against its own live width, gap and skew into `cell_count`.


func test_gap_closes_the_hairline_band() -> void:
	# A ~250px SP bar: pitch alone would pass every count up to 61, all of them
	# rendering as 1-3px slivers once the gap eats its share.
	assert_true(GaugeDensity.ticks_fit(35, 245.6, 4.0, 3.0), "35 cells: 4.0 px of ink")
	assert_false(GaugeDensity.ticks_fit(36, 245.6, 4.0, 3.0), "36 cells: 3.8 px of ink")


func test_gap_defaults_to_zero_so_pitch_only_callers_are_untouched() -> void:
	assert_false(GaugeDensity.ticks_fit(24, 90.0), "3.75 px does not fit")
	assert_true(GaugeDensity.ticks_fit(24, 100.0), "4.17 px fits")
	assert_true(GaugeDensity.ticks_fit(24, 96.0), "exactly MIN_TICK_PX fits")
	assert_true(GaugeDensity.ticks_fit(10, 30.0, 3.0), "custom min_px")


func _pool(width: float = 251.0) -> PoolGauge:
	var g := PoolGauge.new()
	add_child_autofree(g)
	g.size = Vector2(width, 16.0)
	g.cell_gap = 3.0
	return g


func test_pool_gauge_drops_cells_wholesale_past_the_threshold() -> void:
	var g := _pool()
	g.subdivisions = 10
	assert_eq(g.cell_count, 10.0, "22 px of ink per cell")
	g.subdivisions = 80
	assert_eq(g.cell_count, 0.0, "0.1 px of ink: dropped wholesale, never faded")


func test_pool_gauge_re_resolves_on_resize() -> void:
	var g := _pool()
	g.subdivisions = 30
	assert_eq(g.cell_count, 30.0, "fits at 251 px")
	g.size = Vector2(80.0, 16.0)
	assert_eq(g.cell_count, 0.0, "squeezed: ticks drop")
	g.size = Vector2(251.0, 16.0)
	assert_eq(g.cell_count, 30.0, "room again: ticks come back")


func test_unmanaged_gauge_keeps_its_authored_cell_count() -> void:
	var g := _pool()
	g.cell_count = 3.0
	assert_eq(g.subdivisions, PoolGauge.UNMANAGED, "unmanaged is the default")
	g.size = Vector2(40.0, 16.0)
	assert_eq(g.cell_count, 3.0, "authored value is authoritative while unmanaged")


func test_zero_subdivisions_is_a_real_count_not_unmanaged() -> void:
	# A cap-0 pool (Pacifist) has no cells and must draw as none; it renders
	# its out-of-cap surplus through force_cells, not through a stale preview.
	var g := _pool()
	g.cell_count = 3.0
	g.subdivisions = 0
	assert_eq(g.cell_count, 0.0, "zero points, zero cells")


func _composite(height: float = 20.0) -> CompositeBarGauge:
	var g := CompositeBarGauge.new()
	add_child_autofree(g)
	g.size = Vector2(253.0, height)
	g.cell_gap = 3.0
	return g


func test_composite_measures_usable_width_not_size_x() -> void:
	var g := _composite()
	g.skew_degrees = 0.0
	g.subdivisions = 36
	assert_eq(g.cell_count, 36.0, "253 px unskewed: 4.03 px of ink")
	g.skew_degrees = -15.0
	assert_eq(g.cell_count, 0.0, "skew eats 5.4 px: 3.88 px of ink, dropped")


func test_tempo_survives_the_threshold() -> void:
	# Crossing the threshold changes RENDERING, never tempo: a point spent at
	# 34 and at 36 sweeps at the same rate, so the sweep distance comes from
	# the model's point count and not from the (now zero) drawn cells.
	var g := _composite()
	g.size = Vector2(251.0, 20.0)
	g.cell_step_time = 0.2
	g.subdivisions = 80
	assert_eq(g.cell_count, 0.0, "cells dropped at 80 points")
	g.begin_snap()
	g.set_buckets(10.0, 0.0, 0.0, 80.0)
	g.end_snap()
	g.set_buckets(11.0, 0.0, 0.0, 80.0)
	assert_almost_eq(g.shown_fractions.x, 10.0 / 80.0, 0.001,
			"one point still sweeps rather than snapping")
