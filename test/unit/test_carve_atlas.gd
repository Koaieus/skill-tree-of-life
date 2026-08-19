extends GutTest

## The packed CARVE atlas (#247) — the display half of the arbitrary-art
## substrate whose offline bake #246 landed. See docs/domain/emblem-bake.md.
##
## These assertions exist because NEITHER of the project's shader gates can
## catch a wrong slice: GUT runs on the dummy renderer and never samples a
## texture, and the `xvfb-run … opengl3` pass only surfaces GLSL compile
## errors. A corrupted LUT or an off-by-one index renders wrong and passes both.
## So the payload is verified at the Image level here, against the same
## bake_lut() the generator ran — the same shape as #246's determinism test.
##
## Deliberately reads the committed stacked PNG rather than the imported
## Texture2DArray: CompressedTexture2DArray.get_layer_data() returns null under
## the dummy renderer, so an imported-layer assertion would be untestable in
## GUT. What this DOES cover is the committed source of truth; that the importer
## preserves it byte-for-byte was verified once under opengl3 (no
## fix_alpha_border param exists on the 2d_array_texture importer, and
## compress/mode=0 is lossless).

@warning_ignore("shadowed_global_identifier")
const TextureCarveShape = preload("res://skill_node/visuals/emblem/texture_carve_shape.gd")
const InnerDiskScript = preload("res://skill_node/visuals/inner_disk.gd")

const ATLAS_PNG := "res://assets/emblem_luts/carve_atlas.png"
const LIGHTING_INC := "res://skill_node/visuals/lighting.gdshaderinc"


func _atlas() -> CarveAtlas:
	return CarveAtlas.shared()


## The committed stacked PNG, decoded straight from its bytes. NOT
## `Image.load_from_file`, which pushes an "will not work on export" engine
## warning that GUT reports as an unexpected error — and not `load()`, which
## returns the IMPORTED CompressedTexture2DArray whose `get_layer_data()` is
## null under the dummy renderer.
func _stacked() -> Image:
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(ATLAS_PNG))
	return img


## One slice lifted back out of the committed stacked atlas image.
func _slice_image(stacked: Image, slice: int) -> Image:
	var size := TextureCarveShape.LUT_SIZE
	return stacked.get_region(Rect2i(0, size * slice, size, size))


func test_atlas_manifest_is_generated_and_non_empty() -> void:
	var atlas := _atlas()
	assert_not_null(atlas, "run `mise run icons:update` to generate the atlas")
	assert_gt(atlas.slice_paths.size(), 0, "the atlas packs at least one baked LUT")


func test_every_slice_path_points_at_a_committed_lut() -> void:
	for path in _atlas().slice_paths:
		assert_true(ResourceLoader.exists(path), "slice LUT missing: %s" % path)


func test_stacked_atlas_dimensions_match_the_slice_count() -> void:
	var stacked := _stacked()
	var size := TextureCarveShape.LUT_SIZE
	assert_eq(stacked.get_width(), size)
	assert_eq(stacked.get_height(), size * _atlas().slice_paths.size(),
		"one LUT_SIZE-tall slice per manifest entry — the .import's slices/vertical")


## The load-bearing one: each packed slice must be a well-formed CARVE LUT —
## some interior (drop + mask), some exterior, a real depth ramp, and the
## smooth SDF mask. The old byte-for-byte cross-check against bake_lut() is
## gone: the atlas is now baked from the SVG via msdfgen's true SDF
## (tools/bake_svg_sdf.py), not the chamfer path, so there is no shared
## reference implementation to compare against. Off-by-one packing or a stale
## atlas still fail here.
func test_each_slice_is_a_valid_carve_lut() -> void:
	var stacked := _stacked()
	var atlas := _atlas()
	for slice in atlas.slice_paths.size():
		var img := _slice_image(stacked, slice)
		var label := atlas.slice_paths[slice].get_file().get_basename()
		var has_inside := false
		var has_outside := false
		var max_drop := 0.0
		var edge_blend := false
		for y in img.get_height():
			for x in img.get_width():
				var px := img.get_pixel(x, y)
				if px.a > 0.0:
					has_inside = true
					max_drop = maxf(max_drop, px.r)
				else:
					has_outside = true
				if px.a > 0.0 and px.a < 1.0:
					edge_blend = true
		assert_true(has_inside, "slice %d (%s) has no inside texels" % [slice, label])
		assert_true(has_outside, "slice %d (%s) has no outside texels" % [slice, label])
		assert_gt(max_drop, 0.0, "slice %d (%s) has no drop depth" % [slice, label])
		assert_true(edge_blend, "slice %d (%s) lacks the smooth SDF mask" % [slice, label])


func test_slice_of_resolves_a_committed_lut_to_its_index() -> void:
	var atlas := _atlas()
	for slice in atlas.slice_paths.size():
		var lut: Texture2D = load(atlas.slice_paths[slice])
		assert_eq(atlas.slice_of(lut), slice)


func test_slice_of_rejects_an_uncommitted_in_memory_bake() -> void:
	var baked := TextureCarveShape.bake_lut(load("res://assets/icons/spells/spark.png"))
	assert_eq(_atlas().slice_of(baked), CarveAtlas.NO_SLICE,
		"an in-memory bake has no resource_path, so it is not in the atlas")
	assert_eq(_atlas().slice_of(null), CarveAtlas.NO_SLICE)


## The whole point of the indirection: the per-node value is an int index, so
## InnerDisk keeps ONE shared material and its single-draw-call batching (#172).
func test_set_carve_routes_a_texture_shape_to_its_atlas_slice() -> void:
	var atlas := _atlas()
	var shape := TextureCarveShape.new()
	shape.baked_lut = load(atlas.slice_paths[0])

	var disk := InnerDiskScript.new()
	add_child_autofree(disk)
	disk.set_carve(shape.carve(10, &"test"))

	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.TEXTURE)
	assert_eq(disk.effective_carve_slice, 0)


func test_set_carve_falls_back_to_an_empty_dome_for_an_unpacked_lut() -> void:
	var shape := TextureCarveShape.new()
	shape.baked_lut = TextureCarveShape.bake_lut(load("res://assets/icons/spells/spark.png"))

	var disk := InnerDiskScript.new()
	add_child_autofree(disk)
	disk.set_carve(shape.carve(10, &"test"))

	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.NONE,
		"a LUT the atlas doesn't carry renders as the honest empty dome, not a wrong glyph")
	assert_eq(disk.effective_carve_slice, CarveAtlas.NO_SLICE)


## The bake and the decode are two halves of ONE encoding. Nothing at runtime
## notices when they drift — the dent just renders at the wrong depth. This is
## the only automated guard on that, so it reads the constants out of the shader
## source directly.
func test_shader_decode_constants_match_the_bake() -> void:
	var src := FileAccess.get_file_as_string(LIGHTING_INC)
	assert_eq(_shader_const(src, "SN_TEXTURE_DEPTH_SCALE"), TextureCarveShape.DEPTH)
	assert_eq(_shader_const(src, "SN_TEXTURE_GRAD_SCALE"), TextureCarveShape.GRAD_SCALE)


## Constants agreeing is not enough — #318 shipped green past the test above
## because both halves used the same divisor and disagreed on what the
## NUMERATOR meant. The bake emitted drop-per-texel, the shader consumed
## drop-per-unit-p, so every GB texel landed within ~0.002 of neutral 0.5 and
## every texture carve rendered as a blank dome. A units bug is invisible to a
## constants assertion; only the MAGNITUDE of the baked payload sees it.
##
## Threshold: post-fix the deepest interior gradients reach ~0.09 off neutral;
## pre-fix they reached ~0.0015. 0.02 sits an order of magnitude clear of the
## broken encoding without pinning the exact art.
func test_baked_gradients_are_strong_enough_to_perturb_the_normal() -> void:
	const MIN_DEVIATION := 0.02
	var stacked := _stacked()
	var atlas := _atlas()
	for slice in atlas.slice_paths.size():
		var img := _slice_image(stacked, slice)
		var peak := 0.0
		for y in img.get_height():
			for x in img.get_width():
				var px := img.get_pixel(x, y)
				if px.a <= 0.0:
					continue  # outside the silhouette; the shader ignores it
				peak = maxf(peak, maxf(absf(px.g - 0.5), absf(px.b - 0.5)))
		assert_gt(peak, MIN_DEVIATION,
			"slice %d (%s) has a near-neutral GB gradient — it will render as a "
			% [slice, atlas.slice_paths[slice].get_file().get_basename()]
			+ "blank dome. Check _gradient_at's unit conversion (#318).")


func _shader_const(src: String, const_name: String) -> float:
	var re := RegEx.create_from_string("const\\s+float\\s+%s\\s*=\\s*([0-9.]+)" % const_name)
	var m := re.search(src)
	assert_not_null(m, "%s not declared in %s" % [const_name, LIGHTING_INC])
	return float(m.get_string(1)) if m != null else NAN
