extends GutTest

## Pins the cone half of [OverlayFieldTileIndex] (#897): segment bucketing plus
## the projection-dedupe invariant.
##
## Why dedupe is not cosmetic: `field_smin` is NOT idempotent —
## `smin(d, d, k) == d - k/4` — so a primitive folded twice deepens the field,
## and because the duplication comes from the grid it would show up as a
## grid-correlated artefact, not as noise.
##
## The companion circle-side guarantee (fog's gather is bit-identical) is
## carried by test_tile_gather_fold_order_drift.gd and test_vision_source_index.gd,
## which must stay green UNMODIFIED; the last test here restates it directly.

const _K := 0.12


func _cone(a: Vector2, ra: float, b: Vector2, rb: float, tag: float = 0.0) -> Array:
	return [Vector4(a.x, a.y, ra, tag), Vector4(b.x, b.y, rb, 0.0)]


func _random_cones(n: int, span: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for _i in n:
		var a := Vector2(rng.randf_range(-span, span), rng.randf_range(-span, span))
		var b: Vector2 = a + Vector2(rng.randf_range(-span, span), rng.randf_range(-span, span))
		out.append_array(_cone(a, rng.randf_range(4.0, 40.0), b, rng.randf_range(4.0, 40.0)))
	return out


# ---------------------------------------------------------------------------
# The invariant
# ---------------------------------------------------------------------------

## The whole point: a segment spans many cells, so a naive 3×3 concatenation
## meets it more than once.
func test_no_primitive_is_gathered_twice() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC04E1
	var cones := _random_cones(60, 300.0, rng)
	var index := OverlayFieldTileIndex.new()
	index.build_cones(cones, _K)
	for _q in 300:
		var p := Vector2(rng.randf_range(-400.0, 400.0), rng.randf_range(-400.0, 400.0))
		var got: Array = index.gather_tile_order(p)
		var seen: Dictionary = {}
		for i in got:
			assert_false(seen.has(i),
				"primitive %d gathered twice at %s — field_smin is not idempotent" % [i, p])
			seen[i] = true


## Exactness: dedupe drops occurrences, never contributors. Anything the cone
## field can actually reach at `p` must survive the filter.
func test_every_primitive_within_reach_survives_the_dedupe() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC04E2
	var cones := _random_cones(60, 300.0, rng)
	var index := OverlayFieldTileIndex.new()
	index.build_cones(cones, _K)
	var reach := 1.0 + _K
	var checked := 0
	for _q in 400:
		var p := Vector2(rng.randf_range(-400.0, 400.0), rng.randf_range(-400.0, 400.0))
		var got: Dictionary = {}
		for i in index.gather_tile_order(p):
			got[i] = true
		for i in index.primitive_count:
			var texels: Array = index.get_cone(i)
			var d := OverlayFieldCone.distance(
				p, Vector2(texels[0].x, texels[0].y), texels[0].z,
				Vector2(texels[1].x, texels[1].y), texels[1].z)
			if d < reach:
				checked += 1
				assert_true(got.has(i),
					"cone %d contributes at %s (d=%f) but was not gathered" % [i, p, d])
	assert_gt(checked, 100, "the sample must actually hit cones, or this passes vacuously")


## The gather is exactly the projection-bucketed 3×3 — set equality, which is
## what makes the dedupe rule reproducible in the fragment shader.
func test_gather_is_exactly_the_projection_bucketed_neighbourhood() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC04E3
	var cones := _random_cones(40, 250.0, rng)
	var index := OverlayFieldTileIndex.new()
	index.build_cones(cones, _K)
	for _q in 200:
		var p := Vector2(rng.randf_range(-350.0, 350.0), rng.randf_range(-350.0, 350.0))
		var want: Array = []
		var centre := index._cell_of(p)
		for i in index.primitive_count:
			var texels: Array = index.get_cone(i)
			var q := OverlayFieldCone.project(
				p, Vector2(texels[0].x, texels[0].y), Vector2(texels[1].x, texels[1].y))
			var delta: Vector2i = index._cell_of(q) - centre
			if absi(delta.x) <= 1 and absi(delta.y) <= 1:
				want.append(i)
		var got: Array = index.gather_tile_order(p)
		got.sort()
		assert_eq(got, want, "gather at %s must be the projection-bucketed 3×3" % p)


# ---------------------------------------------------------------------------
# Degenerate cones — every owned node ships as one (#140 decision 6)
# ---------------------------------------------------------------------------

func test_a_degenerate_cone_gathers_exactly_like_the_circle_it_is() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD15C0
	var circles: Array = []
	var cones: Array = []
	for _i in 50:
		var c := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
		var r := rng.randf_range(4.0, 40.0)
		circles.append(Vector4(c.x, c.y, r, 0.0))
		cones.append_array(_cone(c, r, c, r))
	var by_circle := OverlayFieldTileIndex.new()
	by_circle.build(circles, _K)
	var by_cone := OverlayFieldTileIndex.new()
	by_cone.build_cones(cones, _K)
	assert_eq(by_cone.cell_size, by_circle.cell_size, "same reach")
	assert_eq(by_cone.grid_origin, by_circle.grid_origin, "same grid")
	for _q in 200:
		var p := Vector2(rng.randf_range(-400.0, 400.0), rng.randf_range(-400.0, 400.0))
		assert_eq(by_cone.gather_tile_order(p), by_circle.gather_tile_order(p),
			"a == b && ra == rb must gather in the same ORDER, not just the same set")


## The fog path's proof obligation restated where the cone work can see it: the
## dedupe filter is a no-op for circles, so build() is untouched behaviour.
func test_circle_build_gathers_every_reachable_circle_in_bucket_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF06
	var circles: Array = []
	for _i in 80:
		circles.append(Vector4(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0),
			rng.randf_range(4.0, 40.0), 0.0))
	var index := OverlayFieldTileIndex.new()
	index.build(circles, _K)
	for _q in 200:
		var p := Vector2(rng.randf_range(-400.0, 400.0), rng.randf_range(-400.0, 400.0))
		var got: Array = index.gather_tile_order(p)
		var want: Array = []
		var centre := index._cell_of(p)
		for i in circles.size():
			var delta: Vector2i = index._cell_of(Vector2(circles[i].x, circles[i].y)) - centre
			if absi(delta.x) <= 1 and absi(delta.y) <= 1:
				want.append(i)
		want.sort()
		var sorted_got: Array = got.duplicate()
		sorted_got.sort()
		assert_eq(sorted_got, want, "no circle may be filtered out by the dedupe")


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func test_cone_layout_is_two_texels_and_the_flat_buffer_counts_occurrences() -> void:
	var cones := _cone(Vector2(0.0, 0.0), 10.0, Vector2(500.0, 0.0), 6.0, 3.0)
	var index := OverlayFieldTileIndex.new()
	index.build_cones(cones, _K)
	assert_eq(index.primitive_count, 1, "two Vector4s are one primitive")
	assert_null(index.circles_texture, "the cone path does not emit the fog's 1-texel format")
	assert_eq(index.primitives_texture.get_width(), 2, "two RGBAF texels per cone")
	var img := index.primitives_texture.get_image()
	assert_eq(img.get_pixel(0, 0), Color(0.0, 0.0, 10.0, 3.0), "texel 0 is (ax, ay, ra, tag)")
	assert_eq(img.get_pixel(1, 0), Color(500.0, 0.0, 6.0, 0.0), "texel 1 is (bx, by, rb, unused)")
	# The segment is ~45 cells long, so the flat index buffer must be sized by
	# bucket occupancy, not by primitive_count.
	assert_gt(index.tile_circle_indices_texture.get_width(), 1,
		"a long cone occupies many cells; the flat buffer sizes to that, not to primitive_count")


func test_empty_and_degenerate_builds_leave_every_texture_null() -> void:
	var index := OverlayFieldTileIndex.new()
	index.build_cones([], _K)
	assert_eq(index.primitive_count, 0)
	assert_null(index.primitives_texture)
	assert_null(index.tile_index_texture)
	index.build_cones(_cone(Vector2.ZERO, 5.0, Vector2.ONE, 5.0), _K)
	assert_not_null(index.primitives_texture)
	index.build([], _K)
	assert_null(index.primitives_texture, "a rebuild must not leave the previous path's texture")
	assert_null(index.circles_texture)
