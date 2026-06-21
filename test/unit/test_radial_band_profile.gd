extends GutTest

## RadialBandProfile: position → band → tag → multiplier.


func _entry(tags: Array) -> ModifierPoolEntry:
	var e := ModifierPoolEntry.new()
	e.id = &"e"
	e.stat_id = &"strength"
	e.operation = StatModifier.Operation.ADD_BASE
	e.value_range = Vector2(1, 1)
	var typed: Array[StringName] = []
	for t in tags:
		typed.append(StringName(t))
	e.tags = typed
	return e


func _profile() -> RadialBandProfile:
	var p := RadialBandProfile.new()
	p.center = Vector2.ZERO
	p.outer_radius = 100.0
	p.band_boundaries = PackedFloat32Array([0.33, 0.66])
	p.band_names = [&"inner", &"mid", &"outer"]
	p.weights = {
		&"outer": {&"rare": 4.0, &"common": 0.5},
		&"inner": {&"common": 2.0},
	}
	return p


func _ctx(pos: Vector2) -> WeightContext:
	var c := WeightContext.new()
	c.position = pos
	return c


func test_outer_band_boosts_rare() -> void:
	var p := _profile()
	var e := _entry([&"str", &"rare"])
	# Position at 80% radius → outer band.
	assert_almost_eq(p.multiplier_for(e, _ctx(Vector2(80, 0))), 4.0, 0.0001)


func test_inner_band_boosts_common() -> void:
	var p := _profile()
	var e := _entry([&"str", &"common"])
	# Position at 10% radius → inner band.
	assert_almost_eq(p.multiplier_for(e, _ctx(Vector2(10, 0))), 2.0, 0.0001)


func test_mid_band_neutral_when_unmentioned() -> void:
	var p := _profile()
	var e := _entry([&"str", &"rare"])
	# Position at 50% radius → mid band. `mid` is not in `weights`.
	assert_almost_eq(p.multiplier_for(e, _ctx(Vector2(50, 0))), 1.0, 0.0001)


func test_outer_band_compresses_common() -> void:
	var p := _profile()
	var e := _entry([&"common"])
	assert_almost_eq(p.multiplier_for(e, _ctx(Vector2(90, 0))), 0.5, 0.0001)


func test_band_for_boundary_uses_upper_band() -> void:
	# Exactly at 0.33 boundary → "mid" (strict <).
	var p := _profile()
	var e := _entry([&"rare"])
	# Mid has no rare entry → 1.0.
	assert_almost_eq(p.multiplier_for(e, _ctx(Vector2(33, 0))), 1.0, 0.0001)


func test_position_beyond_outer_radius_still_uses_last_band() -> void:
	var p := _profile()
	var e := _entry([&"rare"])
	# At ratio 2.0 → still "outer".
	assert_almost_eq(p.multiplier_for(e, _ctx(Vector2(200, 0))), 4.0, 0.0001)
