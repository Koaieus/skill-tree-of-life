extends GutTest

## CarveShape producers (#237's minimal real interface, see
## docs/domain/skillnode-emblem.md): PolygonCarveShape / GemCarveShape ->
## EmblemSpec, and InnerDisk.set_carve()'s dispatch off EmblemSpec.carve_style.

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")
const GemCarveShape = preload("res://skill_node/visuals/emblem/gem_carve_shape.gd")
const InnerDiskScript = preload("res://skill_node/visuals/inner_disk.gd")
const _INNER_DISK_SCENE := preload("res://skill_node/visuals/inner_disk.tscn")


func test_polygon_carve_shape_builds_a_polygon_spec() -> void:
	var shape := PolygonCarveShape.new()
	shape.sides = 5
	shape.squish_x = 0.7
	var spec: EmblemSpec = shape.carve(EmblemSpec.PRIORITY_ARCHETYPE, &"archetype")
	assert_eq(spec.carve_style, EmblemSpec.CarveStyle.POLYGON)
	assert_eq(spec.polygon_sides, 5)
	assert_eq(spec.polygon_squish, 0.7)
	assert_eq(spec.priority, EmblemSpec.PRIORITY_ARCHETYPE)
	assert_eq(spec.source_kind, &"archetype")


func test_polygon_carve_shape_defaults_to_unsquished() -> void:
	var shape := PolygonCarveShape.new()
	shape.sides = 3
	var spec: EmblemSpec = shape.carve(EmblemSpec.PRIORITY_ARCHETYPE, &"archetype")
	assert_eq(spec.polygon_squish, 1.0)


func test_gem_carve_shape_builds_a_gem_spec() -> void:
	var shape := GemCarveShape.new()
	var spec: EmblemSpec = shape.carve(EmblemSpec.PRIORITY_LOOT, &"loot")
	assert_eq(spec.carve_style, EmblemSpec.CarveStyle.GEM)
	assert_eq(spec.priority, EmblemSpec.PRIORITY_LOOT)


func test_inner_disk_set_carve_polygon() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	disk.set_carve(EmblemSpec.polygon_carve(7, EmblemSpec.PRIORITY_ARCHETYPE, &"archetype", 0.8))
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.POLYGON)
	assert_eq(disk.weld_sides, 7)
	assert_eq(disk.weld_squish, 0.8)


func test_inner_disk_set_carve_gem() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	disk.set_carve(EmblemSpec.gem_carve(EmblemSpec.PRIORITY_LOOT, &"loot"))
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.GEM)


func test_inner_disk_set_carve_texture_falls_back_to_none() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	disk.set_carve(EmblemSpec.texture_carve(null, EmblemSpec.PRIORITY_SPELL, &"spell"))
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.NONE, "no renderer yet for TEXTURE carves -> empty dome")


func test_inner_disk_set_carve_null_is_none() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	disk.carve_kind = InnerDiskScript.CarveKind.POLYGON
	disk.set_carve(null)
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.NONE)


# ── Gem LUT bake geometry sanity (side-view kite, not the old top-view crown) ──

func test_gem_table_is_flat_at_the_shapes_center() -> void:
	var centroid := InnerDiskScript._gem_centroid()
	var hg := InnerDiskScript._gem_height_grad(centroid)
	assert_almost_eq(hg.x, InnerDiskScript.GEM_DEPTH, 0.001, "table facet is flat at full depth near the shape's center")
	assert_almost_eq(hg.y, 0.0, 0.001)
	assert_almost_eq(hg.z, 0.0, 0.001)


func test_gem_is_asymmetric_top_to_bottom() -> void:
	# Pointy south, flat top: a point near the top edge should be INSIDE
	# (near the flat table), the mirrored point near the bottom should be
	# OUTSIDE (past the pavilion's point).
	var near_top := Vector2(0.0, InnerDiskScript.GEM_TOP_Y - 0.05)
	var near_bottom := Vector2(0.0, InnerDiskScript.GEM_POINT_Y + 0.05)
	assert_true(InnerDiskScript._gem_inside(near_top), "near the flat table edge should read as inside")
	assert_true(InnerDiskScript._gem_inside(near_bottom), "just above the point should still read as inside")
	assert_false(InnerDiskScript._gem_inside(Vector2(0.0, InnerDiskScript.GEM_POINT_Y - 0.05)), "past the point should be outside")
	assert_false(InnerDiskScript._gem_inside(Vector2(0.0, InnerDiskScript.GEM_TOP_Y + 0.05)), "past the flat top edge should be outside")


func test_gem_outside_shape_has_zero_drop() -> void:
	var hg := InnerDiskScript._gem_height_grad(Vector2(0.99, 0.99))
	assert_eq(hg, Vector3.ZERO)
