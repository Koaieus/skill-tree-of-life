extends GutTest

## #843 — `InnerDisk.carve_params()` is the typed carve a shatter carries: it
## must equal the disk's own `effective_*` getters for every CarveKind, and
## its texel packing must round-trip exactly (32-bit RGBAF, so integers are
## exact and floats survive at float32).

const _DISK_SCENE := preload("res://skill_node/visuals/inner_disk.tscn")
const InnerDiskScript = preload("res://skill_node/visuals/inner_disk.gd")
@warning_ignore("shadowed_global_identifier")
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
@warning_ignore("shadowed_global_identifier")
const TextureCarveShape = preload("res://skill_node/visuals/emblem/texture_carve_shape.gd")

var _disk: Node


func before_each() -> void:
	_disk = _DISK_SCENE.instantiate()
	add_child_autofree(_disk)


func _assert_matches_getters(expected_kind: int) -> CarveParams:
	var p: CarveParams = _disk.carve_params()
	assert_not_null(p)
	assert_eq(p.carve_kind, expected_kind, "kind")
	assert_eq(p.carve_kind, int(_disk.effective_carve_kind))
	assert_eq(p.carve_sides, int(_disk.effective_carve_sides))
	assert_eq(p.carve_squish, float(_disk.effective_carve_squish))
	assert_eq(p.carve_radius, float(_disk.effective_carve_radius))
	assert_eq(p.well_depth, float(_disk.effective_well_depth))
	assert_eq(p.carve_slice, int(_disk.effective_carve_slice))
	assert_eq(p.carve_slice_b, int(_disk.effective_carve_slice_b))
	_assert_round_trips(p)
	return p


func _assert_round_trips(p: CarveParams) -> void:
	var texels := p.to_texels()
	assert_eq(texels.size(), CarveParams.TEXELS)
	var back := CarveParams.from_texels(texels[0], texels[1])
	assert_eq(back.to_texels(), texels, "texels round-trip bit-exactly")
	assert_eq(back.carve_kind, p.carve_kind)
	assert_eq(back.carve_sides, p.carve_sides)
	assert_eq(back.carve_slice, p.carve_slice)
	assert_eq(back.carve_slice_b, p.carve_slice_b)
	assert_almost_eq(back.carve_squish, p.carve_squish, 1e-6)
	assert_almost_eq(back.carve_radius, p.carve_radius, 1e-6)
	assert_almost_eq(back.well_depth, p.well_depth, 1e-6)
	assert_true(back.equals(p))


func test_none_is_the_empty_dome() -> void:
	_disk.set_carve(null)
	var p := _assert_matches_getters(InnerDiskScript.CarveKind.NONE)
	assert_true(p.equals(CarveParams.none()))


func test_polygon_carries_its_procedural_knobs() -> void:
	var shape := PolygonCarveShape.new()
	shape.sides = 5
	shape.squish_x = 0.8
	shape.radius = 0.9
	shape.well_depth = 0.6
	_disk.set_carve(shape.carve(EmblemSpec.Priority.SPELL, &"poly"))
	var p := _assert_matches_getters(InnerDiskScript.CarveKind.POLYGON)
	assert_eq(p.carve_sides, 5)


func test_gem_reads_the_shared_lut() -> void:
	_disk.set_carve(GemCarveShape.new().carve(EmblemSpec.Priority.SPELL, &"gem"))
	_assert_matches_getters(InnerDiskScript.CarveKind.GEM)


func test_texture_carries_both_atlas_slices_of_a_spell_tie() -> void:
	var atlas := CarveAtlas.shared()
	assert_not_null(atlas, "the committed carve atlas")
	if atlas == null or atlas.slice_paths.size() < 2:
		fail_test("need two committed atlas slices")
		return
	var a := TextureCarveShape.new()
	a.baked_lut = load(atlas.slice_paths[0])
	var b := TextureCarveShape.new()
	b.baked_lut = load(atlas.slice_paths[1])
	var sa := a.carve(EmblemSpec.Priority.SPELL, &"a")
	var sb := b.carve(EmblemSpec.Priority.SPELL, &"b")
	_disk.set_carve(sa, [sa, sb])
	var p := _assert_matches_getters(InnerDiskScript.CarveKind.TEXTURE)
	assert_eq(p.carve_slice, 0)
	assert_eq(p.carve_slice_b, 1)
