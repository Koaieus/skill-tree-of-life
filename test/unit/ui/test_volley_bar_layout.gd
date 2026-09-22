extends GutTest
## VolleyBar.layout is pure geometry: typed segment rects tiling the filled
## width, a wave notch at every wave boundary, and per-arrow ticks only when
## GaugeDensity says they are legible.

const SEGS: Array[Dictionary] = [
	{"type_id": &"arrow", "count": 6},
	{"type_id": &"poison", "count": 3},
]


func _segs(n: int) -> Array[Dictionary]:
	return [{"type_id": &"arrow", "count": n}]


func test_wave_notches_and_arrow_ticks_at_30px_pitch() -> void:
	var lay := VolleyBar.layout(9, 11, PackedInt32Array([3, 6, 9]), SEGS, 330.0)
	assert_eq(Array(lay["wave_x"]), [90.0, 180.0, 270.0], "wave notch at every wave boundary")
	var arrows: PackedFloat32Array = lay["arrow_x"]
	assert_eq(arrows.size(), 10, "one tick per arrow boundary strictly inside the track")
	for i in arrows.size():
		assert_almost_eq(arrows[i], 30.0 * float(i + 1), 0.001, "arrow tick %d at 30 px pitch" % i)
	assert_false(lay["arrows_suppressed"], "30 px pitch is legible")


func test_arrow_ticks_suppressed_below_threshold_waves_kept() -> void:
	var notches := PackedInt32Array([30, 60])
	var dense := VolleyBar.layout(90, 90, notches, _segs(90), 300.0)
	assert_eq((dense["arrow_x"] as PackedFloat32Array).size(), 0, "3.3 px pitch: no arrow ticks")
	assert_true(dense["arrows_suppressed"])
	assert_eq(Array(dense["wave_x"]), [100.0, 200.0], "wave notches always drawn")
	var fits := VolleyBar.layout(60, 60, PackedInt32Array([20, 40]), _segs(60), 300.0)
	assert_eq((fits["arrow_x"] as PackedFloat32Array).size(), 59, "5 px pitch: ticks drawn")
	assert_false(fits["arrows_suppressed"])


func test_gauge_density_threshold_is_inclusive() -> void:
	assert_false(GaugeDensity.ticks_fit(24, 90.0), "3.75 px does not fit")
	assert_true(GaugeDensity.ticks_fit(24, 100.0), "4.17 px fits")
	assert_true(GaugeDensity.ticks_fit(24, 96.0), "exactly MIN_TICK_PX fits")
	assert_true(GaugeDensity.ticks_fit(10, 30.0, 3.0), "custom min_px")


func test_segments_tile_the_filled_width_exactly() -> void:
	var lay := VolleyBar.layout(9, 11, PackedInt32Array([3, 6, 9]), SEGS, 330.0)
	var segs: Array = lay["segments"]
	assert_eq(segs.size(), 2)
	var x := 0.0
	var total := 0.0
	for seg in segs:
		assert_almost_eq(float(seg["x"]), x, 0.001, "segments abut")
		x += float(seg["w"])
		total += float(seg["w"])
	assert_almost_eq(total, 30.0 * 9.0, 0.001, "sum of widths == px_per * n")
	assert_eq(segs[0]["tint"], VolleyBar.TYPE_TINTS[&"arrow"])
	assert_eq(segs[1]["tint"], VolleyBar.TYPE_TINTS[&"poison"])
