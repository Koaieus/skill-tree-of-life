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


## Base-mip pixels only, as a short digest.
##
## Blitting into a fresh mipmap-less image is load-bearing: `bake_lut()`'s
## result carries a mip chain and a decoded PNG doesn't, and `get_data()`
## includes that chain — so comparing the two raw byte arrays fails on LENGTH
## even when every visible pixel agrees (verified: 0 pixel differences while
## the raw arrays differed). Hashing keeps a real failure readable too;
## comparing the arrays directly dumps ~500KB per slice into the log.
func _digest(img: Image) -> String:
	var size := TextureCarveShape.LUT_SIZE
	var base := Image.create(size, size, false, Image.FORMAT_RGBA8)
	base.blit_rect(img, Rect2i(0, 0, size, size), Vector2i.ZERO)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(base.get_data())
	return ctx.finish().hex_encode()


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


## The load-bearing one: each packed slice must be exactly what the bake
## produces for that icon. Off-by-one packing, a stale atlas, or an importer
## that mangled the payload all fail here.
func test_each_slice_is_the_bake_of_its_source_icon() -> void:
	var stacked := _stacked()
	var atlas := _atlas()
	for slice in atlas.slice_paths.size():
		var name := atlas.slice_paths[slice].get_file().get_basename()
		var source: Texture2D = load("res://assets/icons/spells/%s.png" % name)
		assert_not_null(source, "no source icon for slice %d (%s)" % [slice, name])
		var expected := TextureCarveShape.bake_lut(source).get_image()
		assert_eq(_digest(_slice_image(stacked, slice)), _digest(expected),
			"slice %d (%s) is stale — re-run `mise run icons:update`" % [slice, name])


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


func _shader_const(src: String, name: String) -> float:
	var re := RegEx.create_from_string("const\\s+float\\s+%s\\s*=\\s*([0-9.]+)" % name)
	var m := re.search(src)
	assert_not_null(m, "%s not declared in %s" % [name, LIGHTING_INC])
	return float(m.get_string(1)) if m != null else NAN
