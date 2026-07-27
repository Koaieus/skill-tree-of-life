extends GutTest

## CarveShape producers (#237's minimal real interface, see
## docs/domain/skillnode-emblem.md): PolygonCarveShape / GemCarveShape ->
## EmblemSpec, and InnerDisk.set_carve()'s dispatch off EmblemSpec.carve_style.

const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")
const GemCarveShape = preload("res://skill_node/visuals/emblem/gem_carve_shape.gd")
const InnerDiskScript = preload("res://skill_node/visuals/inner_disk.gd")
const _INNER_DISK_SCENE := preload("res://skill_node/visuals/inner_disk.tscn")
const _COMPOSITE_SCENE := preload("res://skill_node/visuals/node_visuals_composite.tscn")


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
	# Disk space is +Y DOWN, so the table is at the MOST NEGATIVE y and the
	# culet at the most positive. Just inside either should read as inside;
	# just past either as outside.
	var below_table := Vector2(0.0, InnerDiskScript.GEM_TABLE_Y + 0.05)
	var above_culet := Vector2(0.0, InnerDiskScript.GEM_CULET_Y - 0.05)
	assert_true(InnerDiskScript._gem_inside(below_table), "just below the flat table edge should read as inside")
	assert_true(InnerDiskScript._gem_inside(above_culet), "just above the culet should still read as inside")
	assert_false(InnerDiskScript._gem_inside(Vector2(0.0, InnerDiskScript.GEM_CULET_Y + 0.05)), "past the culet should be outside")
	assert_false(InnerDiskScript._gem_inside(Vector2(0.0, InnerDiskScript.GEM_TABLE_Y - 0.05)), "above the flat table edge should be outside")


## The test the ORIGINAL gem geometry suite could not fail: every other
## assertion here works in disk space and is self-consistent inside it, so a
## silhouette baked upside-down (math-convention +Y-up vertices written into
## +Y-down image rows) passed everything while rendering culet-up. Measuring
## the baked LUT's per-row coverage is what ties the geometry to what the
## sprite actually shows.
func test_baked_gem_lut_has_the_table_at_the_top() -> void:
	var img := (InnerDiskScript._build_gem_lut() as ImageTexture).get_image()
	var h := img.get_height()
	# Probe just inside the silhouette's own vertical extent, top and bottom.
	var top_span := _covered_span(img, _row_at(h, InnerDiskScript.GEM_TABLE_Y + 0.03))
	var bottom_span := _covered_span(img, _row_at(h, InnerDiskScript.GEM_CULET_Y - 0.03))
	assert_gt(top_span, bottom_span * 5,
		"the wide flat table must occupy the TOP rows of the LUT and the culet point the bottom")


## LUT image row holding disk-space y (-1..1 maps to row 0..height).
func _row_at(height: int, y: float) -> int:
	return clampi(int((y * 0.5 + 0.5) * height), 0, height - 1)


## Count of texels in `row` with meaningful silhouette coverage.
func _covered_span(img: Image, row: int) -> int:
	var n := 0
	for x in img.get_width():
		if img.get_pixel(x, row).a > 0.5:
			n += 1
	return n


func test_gem_edge_coverage_is_antialiased() -> void:
	# A hard 0/1 alpha is what stair-stepped the outline. Sample straight
	# across the girdle's left edge: coverage must pass through intermediate
	# values, not jump.
	var y := InnerDiskScript.GEM_GIRDLE_Y
	var edge_x := -InnerDiskScript.GEM_GIRDLE_HALF_WIDTH
	assert_almost_eq(InnerDiskScript._gem_coverage(Vector2(edge_x, y)), 0.5, 0.05,
		"exactly on the outline should be half-covered")
	assert_eq(InnerDiskScript._gem_coverage(Vector2(edge_x + 0.2, y)), 1.0, "well inside is fully covered")
	assert_eq(InnerDiskScript._gem_coverage(Vector2(edge_x - 0.2, y)), 0.0, "well outside is uncovered")


## Structural invariants of "reads as a gem", NOT specific tuned ratios — the
## three GEM_*_RATIO knobs are meant to be dialled in a screenshot loop, and a
## test asserting their current values would just fight that. What must hold no
## matter how they're tuned:
func test_gem_silhouette_invariants() -> void:
	assert_lt(InnerDiskScript.GEM_TABLE_HALF_WIDTH, InnerDiskScript.GEM_GIRDLE_HALF_WIDTH,
		"the table is narrower than the girdle, else the crown has no taper")
	assert_lt(InnerDiskScript.GEM_CROWN_HEIGHT, InnerDiskScript.GEM_PAVILION_DEPTH,
		"the pavilion is deeper than the crown is tall — the asymmetry IS the gem read")
	assert_gt(InnerDiskScript.GEM_TABLE_HALF_WIDTH, 0.0, "a gem has a flat table, not a point")
	# Must fit the -1..1 disk the shader samples, or the silhouette clips.
	for v: Vector2 in InnerDiskScript.GEM_VERTICES:
		assert_lt(v.length(), 1.0, "vertex %s must sit inside the unit disk" % v)


func test_gem_outside_shape_has_zero_drop() -> void:
	var hg := InnerDiskScript._gem_height_grad(Vector2(0.99, 0.99))
	assert_eq(hg, Vector3.ZERO)


## NodeVisualsComposite.carve_shape — the single authored shape knob, added so
## the composite (the node a designer would look at) can actually preview a
## shape without drilling into InnerDisk's standalone-preview fallbacks.
func test_composite_carve_shape_export_reaches_the_disk() -> void:
	var composite = _COMPOSITE_SCENE.instantiate()
	autofree(composite)
	add_child(composite)
	await get_tree().process_frame
	var shape := PolygonCarveShape.new()
	shape.sides = 5
	shape.squish_x = 0.7
	composite.carve_shape = shape
	var disk = composite.get_node("ShaderStack/InnerDisk")
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.POLYGON)
	assert_eq(disk.weld_sides, 5)
	assert_almost_eq(disk.weld_squish, 0.7, 0.001)


## Null must mean "nothing authored", NOT "carve nothing" — clearing it to
## null on _ready would flatten InnerDisk's own authored preview knobs.
func test_composite_null_carve_shape_leaves_the_disks_own_knobs_alone() -> void:
	var composite = _COMPOSITE_SCENE.instantiate()
	autofree(composite)
	var disk = composite.get_node("ShaderStack/InnerDisk")
	disk.carve_kind = InnerDiskScript.CarveKind.POLYGON
	disk.weld_sides = 6
	add_child(composite)
	await get_tree().process_frame
	assert_eq(composite.carve_shape, null, "default is null")
	assert_eq(disk.carve_kind, InnerDiskScript.CarveKind.POLYGON, "the disk's authored carve survives")
	assert_eq(disk.weld_sides, 6)
