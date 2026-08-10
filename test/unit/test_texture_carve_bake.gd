extends GutTest

## TextureCarveShape's offline bake (#246) — headless, no renderer, no editor.
## Drives TextureCarveShape.bake_lut() directly against a real spell icon and
## asserts on the encoding contract InnerDisk's gem LUT already established
## (see .claude/rules/skill-node-visuals.md and docs/domain/emblem-bake.md).

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const TextureCarveShape = preload("res://skill_node/visuals/emblem/texture_carve_shape.gd")

const SOURCE_ICON := "res://assets/icons/spells/lightning_bolt.png"
const COMMITTED_LUT := "res://assets/emblem_luts/lightning_bolt.png"


func _load_source() -> Texture2D:
	return load(SOURCE_ICON) as Texture2D


## The bolt silhouette is a thin zigzag, not a filled disc — it doesn't
## necessarily cover the LUT's exact center. Scan for the deepest (most
## interior) inside texel instead of assuming any fixed coordinate.
func _find_deepest_texel(img: Image) -> Vector2i:
	var size := TextureCarveShape.LUT_SIZE
	var best := Vector2i(-1, -1)
	var best_r := -1.0
	for y in size:
		for x in size:
			var px := img.get_pixel(x, y)
			if px.a > 0.0 and px.r > best_r:
				best_r = px.r
				best = Vector2i(x, y)
	return best


func test_baked_lut_is_rgba8_square_with_mipmaps() -> void:
	var tex := TextureCarveShape.bake_lut(_load_source())
	var img := tex.get_image()
	assert_eq(img.get_format(), Image.FORMAT_RGBA8)
	assert_eq(img.get_width(), TextureCarveShape.LUT_SIZE)
	assert_eq(img.get_height(), TextureCarveShape.LUT_SIZE)
	assert_true(img.has_mipmaps(), "baked LUT must carry mipmaps (minification sampling, see InnerDisk gem LUT precedent)")


func test_alpha_channel_marks_the_inside_mask() -> void:
	var tex := TextureCarveShape.bake_lut(_load_source())
	var img := tex.get_image()

	var deepest := _find_deepest_texel(img)
	assert_true(deepest.x >= 0, "there should be at least one inside texel")
	var inside := img.get_pixel(deepest.x, deepest.y)
	assert_eq(inside.a, 1.0, "the deepest interior texel should read inside")

	# The corner is off any centered icon art (see the ascii dump in the
	# handoff notes) and reliably outside the silhouette.
	var corner := img.get_pixel(1, 1)
	assert_eq(corner.a, 0.0, "corner, off any centered icon, should read outside")


func test_intaglio_depth_ramps_from_edge_to_interior() -> void:
	var tex := TextureCarveShape.bake_lut(_load_source())
	var img := tex.get_image()
	var size := TextureCarveShape.LUT_SIZE

	var deepest := _find_deepest_texel(img)
	assert_true(deepest.x >= 0, "there should be at least one inside texel")
	var interior := img.get_pixel(deepest.x, deepest.y)
	assert_true(interior.a > 0.0, "sampling point must actually be inside the mask")
	assert_gt(interior.r, 0.0, "interior drop must be positive (a dent, not a bump)")

	# Walk out from the deepest texel along +x until we find the boundary
	# (last inside texel before falling outside) to compare depth.
	var near_edge_r := interior.r
	var cy := deepest.y
	for x in range(deepest.x, size):
		var px := img.get_pixel(x, cy)
		if px.a <= 0.0:
			var last_inside := img.get_pixel(x - 1, cy)
			near_edge_r = last_inside.r
			break

	assert_true(interior.r > near_edge_r, "interior should be deeper than a texel near the silhouette edge")
	assert_almost_eq(near_edge_r, 0.0, 0.15, "depth should ramp down toward ~0 near the edge")


func test_gradient_channels_are_a_valid_remap() -> void:
	var tex := TextureCarveShape.bake_lut(_load_source())
	var img := tex.get_image()
	var size := TextureCarveShape.LUT_SIZE

	for y in size:
		for x in size:
			var px := img.get_pixel(x, y)
			assert_true(px.g >= 0.0 and px.g <= 1.0, "G channel out of 0..1 remap range")
			assert_true(px.b >= 0.0 and px.b <= 1.0, "B channel out of 0..1 remap range")

	# The deepest interior texel sits at (an approximation of) a local maximum
	# of the drop field, i.e. a locally flat point -> gradient ~0 -> GB ~0.5.
	var deepest := _find_deepest_texel(img)
	assert_true(deepest.x >= 0, "there should be at least one inside texel")
	var peak := img.get_pixel(deepest.x, deepest.y)
	assert_almost_eq(peak.g, 0.5, 0.1, "gradient should be ~flat at the drop field's own local maximum")
	assert_almost_eq(peak.b, 0.5, 0.1, "gradient should be ~flat at the drop field's own local maximum")


func test_bake_is_deterministic() -> void:
	var source := _load_source()
	var a := TextureCarveShape.bake_lut(source).get_image()
	var b := TextureCarveShape.bake_lut(source).get_image()
	assert_eq(a.get_data(), b.get_data(), "baking the same source twice must yield byte-identical images")


func test_carve_returns_a_spec_carrying_the_shape_itself() -> void:
	var shape := TextureCarveShape.new()
	shape.source_texture = _load_source()
	shape.baked_lut = TextureCarveShape.bake_lut(shape.source_texture)

	var spec: EmblemSpec = shape.carve(EmblemSpec.Priority.SPELL, &"spell")
	assert_same(spec.shape, shape, "the spec carries the shape; #247's decode reads baked_lut off it")
	assert_eq(spec.shape.baked_lut, shape.baked_lut)
	assert_eq(spec.priority, EmblemSpec.Priority.SPELL)
	assert_eq(spec.source_kind, &"spell")


## The "Bake" tool button must never clobber a committed pipeline LUT: the
## spell defs wire baked_lut to the SVG-baked assets in assets/emblem_luts/,
## and a chamfer re-bake from the raster source would silently swap the
## pristine SDF field for the degraded one (see docs/domain/emblem-bake.md).
func test_bake_button_refuses_to_overwrite_a_committed_lut() -> void:
	var shape := TextureCarveShape.new()
	shape.source_texture = _load_source()
	shape.baked_lut = load(COMMITTED_LUT)
	var before_path := shape.baked_lut.resource_path
	assert_true(not before_path.is_empty(), "the committed LUT must resolve by resource_path")

	shape._bake_from_source()

	assert_eq(shape.baked_lut.resource_path, before_path,
		"the pristine pipeline LUT must survive a Bake button press")
	assert_push_warning("refusing to overwrite committed LUT")


func test_bake_button_without_a_committed_lut_still_bakes() -> void:
	var shape := TextureCarveShape.new()
	shape.source_texture = _load_source()

	shape._bake_from_source()

	assert_not_null(shape.baked_lut)
	assert_true(shape.baked_lut.resource_path.is_empty(),
		"an in-memory bake has no resource_path — it is not committed")
