extends GutTest

## CarveShape producers (#237's minimal real interface, see
## docs/domain/skillnode-emblem.md): PolygonCarveShape / GemCarveShape ->
## EmblemSpec, and InnerDisk.set_carve()'s dispatch off the spec's own shape
## TYPE (#315 retired the CarveStyle enum that used to echo it).

@warning_ignore("shadowed_global_identifier")
const EmblemSpec = preload("res://skill_node/visuals/emblem/emblem_spec.gd")
@warning_ignore("shadowed_global_identifier")
const PolygonCarveShape = preload("res://skill_node/visuals/emblem/polygon_carve_shape.gd")
@warning_ignore("shadowed_global_identifier")
const GemCarveShape = preload("res://skill_node/visuals/emblem/gem_carve_shape.gd")
@warning_ignore("shadowed_global_identifier")
const TextureCarveShape = preload("res://skill_node/visuals/emblem/texture_carve_shape.gd")
const InnerDiskScript = preload("res://skill_node/visuals/inner_disk.gd")
const _INNER_DISK_SCENE := preload("res://skill_node/visuals/inner_disk.tscn")
const _COMPOSITE_SCENE := preload("res://skill_node/visuals/node_visuals_composite.tscn")


func test_polygon_carve_shape_builds_a_polygon_spec() -> void:
	var shape := PolygonCarveShape.new()
	shape.sides = 5
	shape.squish_x = 0.7
	var spec: EmblemSpec = shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype")
	assert_same(spec.shape, shape, "the spec carries the SHAPE, not a copy of its fields")
	assert_eq(spec.shape.sides, 5)
	assert_eq(spec.shape.squish_x, 0.7)
	assert_eq(spec.priority, EmblemSpec.Priority.ARCHETYPE)
	assert_eq(spec.source_kind, &"archetype")


func test_polygon_carve_shape_defaults_to_unsquished() -> void:
	var shape := PolygonCarveShape.new()
	shape.sides = 3
	var spec: EmblemSpec = shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype")
	assert_eq(spec.shape.squish_x, 1.0)


func test_gem_carve_shape_builds_a_gem_spec() -> void:
	var shape := GemCarveShape.new()
	var spec: EmblemSpec = shape.carve(EmblemSpec.Priority.LOOT, &"loot")
	assert_same(spec.shape, shape)
	assert_eq(spec.priority, EmblemSpec.Priority.LOOT)


func test_gem_carve_shape_has_one_shared_instance() -> void:
	assert_not_null(GemCarveShape.SHARED, "the parameterless gem shape ships a shared instance (#315)")
	assert_same(GemCarveShape.SHARED, GemCarveShape.SHARED, "and it is the same object every read")


func test_inner_disk_set_carve_polygon() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	var shape := PolygonCarveShape.new()
	shape.sides = 7
	shape.squish_x = 0.8
	disk.set_carve(shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype"))
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.POLYGON)
	assert_eq(disk.effective_carve_sides, 7)
	assert_eq(disk.effective_carve_squish, 0.8)


func test_inner_disk_set_carve_gem() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	disk.set_carve(GemCarveShape.SHARED.carve(EmblemSpec.Priority.LOOT, &"loot"))
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.GEM)


func test_inner_disk_set_carve_texture_falls_back_to_none() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	disk.set_carve(TextureCarveShape.new().carve(EmblemSpec.Priority.SPELL, &"spell"))
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.NONE, "no renderer yet for TEXTURE carves -> empty dome")


## A spec whose shape is null is NOT the same as no contribution: the source
## claims its rung and reads as an empty dome. See SkillNode.get_emblem_contributions.
func test_inner_disk_set_carve_shapeless_spec_is_none() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	disk.carve_shape = PolygonCarveShape.new()
	disk.set_carve(EmblemSpec.carve(null, EmblemSpec.Priority.KEYSTONE, &"keystone"))
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.NONE,
		"a spec with no shape claims its rung and reads as an empty dome — it does NOT fall back to the authored carve_shape")


func test_inner_disk_set_carve_null_is_none() -> void:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	await get_tree().process_frame
	disk.carve_shape = PolygonCarveShape.new()
	disk.set_carve(null)
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.NONE,
		"set_carve(null) resolves to an honest empty dome, not the authored carve_shape")


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
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.POLYGON)
	assert_eq(disk.effective_carve_sides, 5)
	assert_almost_eq(disk.effective_carve_squish, 0.7, 0.001)


## Null must mean "nothing authored", NOT "carve nothing" — clearing it to
## null on _ready would flatten InnerDisk's own authored carve_shape.
func test_composite_null_carve_shape_leaves_the_disks_own_authored_shape_alone() -> void:
	var composite = _COMPOSITE_SCENE.instantiate()
	autofree(composite)
	var disk = composite.get_node("ShaderStack/InnerDisk")
	var authored := PolygonCarveShape.new()
	authored.sides = 6
	disk.carve_shape = authored
	add_child(composite)
	await get_tree().process_frame
	assert_eq(composite.carve_shape, null, "default is null")
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.POLYGON, "the disk's authored carve survives")
	assert_eq(disk.effective_carve_sides, 6)


## ...but once a shape HAS been applied, clearing the export back to null must
## actually clear the carve, not leave the stale one stuck on the disk.
func test_composite_clearing_an_applied_carve_shape_clears_the_disk() -> void:
	var composite = _COMPOSITE_SCENE.instantiate()
	autofree(composite)
	add_child(composite)
	await get_tree().process_frame
	var shape := PolygonCarveShape.new()
	shape.sides = 5
	composite.carve_shape = shape
	var disk = composite.get_node("ShaderStack/InnerDisk")
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.POLYGON, "applied")
	composite.carve_shape = null
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.NONE, "and cleared again")


# ── #285: the geometry lives on the shape, and the disk's exports stay authored ──

func _disk_in_tree() -> Node:
	var disk := _INNER_DISK_SCENE.instantiate()
	autofree(disk)
	add_child(disk)
	return disk


func test_shape_radius_reaches_the_disk() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	var small := PolygonCarveShape.new()
	small.radius = 0.5
	var big := PolygonCarveShape.new()
	big.radius = 1.1

	disk.set_carve(small.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype"))
	var small_r: float = disk.effective_carve_radius
	disk.set_carve(big.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype"))
	var big_r: float = disk.effective_carve_radius

	assert_almost_eq(small_r, 0.5, 0.001)
	assert_almost_eq(big_r, 1.1, 0.001)
	assert_ne(small_r, big_r, "two shapes differing only in radius must carve at different sizes")


func test_negative_shape_well_depth_inherits_the_disks_own() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	disk.well_depth = 0.42
	var shape := PolygonCarveShape.new()
	assert_almost_eq(shape.well_depth, -1.0, 0.001, "shapes inherit the disk's depth by default")
	disk.set_carve(shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype"))
	assert_almost_eq(disk.effective_well_depth, 0.42, 0.001)


func test_shape_may_override_well_depth() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	disk.well_depth = 0.42
	var shape := PolygonCarveShape.new()
	shape.well_depth = 0.5
	disk.set_carve(shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype"))
	assert_almost_eq(disk.effective_well_depth, 0.5, 0.001)


## The sentinel must be resolved on the CPU: the shader's uniform is
## hint_range(0.0, 1.0), so a negative would clamp to 0.0 — "no dent" — and
## silently flatten every shape that inherits.
func test_the_inherit_sentinel_never_reaches_the_shader() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	disk.well_depth = 0.42
	disk.set_carve(PolygonCarveShape.new().carve(EmblemSpec.Priority.ARCHETYPE, &"archetype"))
	var pushed = disk.get_instance_shader_parameter(&"well_depth")
	assert_not_null(pushed, "the uniform must actually have been pushed, or this asserts nothing")
	assert_almost_eq(float(pushed), 0.42, 0.001, "the -1.0 sentinel resolved to the disk's own depth")


## set_carve() writing an @export is the "@tool script writes a derived value
## into an @export" trap — the editor then serialises it into the .tscn and the
## next load computes again from there. See .claude/rules/godot-workflow.md.
func test_set_carve_writes_no_exported_property() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	var authored := PolygonCarveShape.new()
	authored.sides = 4
	disk.carve_shape = authored
	disk.well_depth = 0.35

	var shape := PolygonCarveShape.new()
	shape.sides = 9
	shape.squish_x = 0.4
	shape.radius = 1.1
	shape.well_depth = 0.8
	disk.set_carve(shape.carve(EmblemSpec.Priority.ARCHETYPE, &"archetype"))

	assert_same(disk.carve_shape, authored, "authored carve_shape untouched")
	assert_almost_eq(disk.well_depth, 0.35, 0.001, "authored well_depth untouched")
	assert_eq(disk.effective_carve_sides, 9, "...while the resolved shape is what renders")


## The authored carve_shape is what renders until a carve RESOLVES — the
## reopen of #285 replaced the four scalar preview knobs with one shape.
func test_authored_carve_shape_drives_the_effective_carve() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	var shape := PolygonCarveShape.new()
	shape.sides = 5
	shape.squish_x = 0.7
	shape.radius = 0.9
	disk.carve_shape = shape
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.POLYGON)
	assert_eq(disk.effective_carve_sides, 5)
	assert_almost_eq(disk.effective_carve_squish, 0.7, 0.001)
	assert_almost_eq(disk.effective_carve_radius, 0.9, 0.001)


func test_null_authored_carve_shape_is_the_empty_dome() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.NONE)
	assert_eq(disk.effective_carve_sides, 3, "fallback defaults render, not a phantom shape")
	assert_almost_eq(disk.effective_carve_squish, 1.0, 0.001)
	assert_almost_eq(disk.effective_carve_radius, 0.75, 0.001)


## A RESOLVED carve outranks the authored shape; resolving to nothing reads as
## an honest empty dome, not a fallback to the authored carve.
func test_resolved_carve_outranks_the_authored_shape() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	disk.carve_shape = PolygonCarveShape.new()
	disk.set_carve(null)
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.NONE,
		"a resolved empty carve does NOT fall back to the authored carve_shape")


## The same inherit/override well_depth dial the resolved path honors, on the
## authored channel (#285 reopen: a preview shape may bring its own depth).
func test_authored_shape_may_override_well_depth() -> void:
	var disk := _disk_in_tree()
	await get_tree().process_frame
	disk.well_depth = 0.42
	var shape := PolygonCarveShape.new()
	shape.well_depth = 0.5
	disk.carve_shape = shape
	assert_almost_eq(disk.effective_well_depth, 0.5, 0.001)


## The composite routes its authored shape into the disk's OWN authored slot —
## it composes and routes, it doesn't interpret, and it doesn't consume the
## runtime resolution channel.
func test_composite_carve_shape_routes_into_the_disks_authored_slot() -> void:
	var composite = _COMPOSITE_SCENE.instantiate()
	autofree(composite)
	add_child(composite)
	await get_tree().process_frame
	var shape := PolygonCarveShape.new()
	shape.sides = 5
	composite.carve_shape = shape
	var disk = composite.get_node("ShaderStack/InnerDisk")
	assert_same(disk.carve_shape, shape, "the disk's authored slot holds the composite's shape")
	assert_eq(disk.effective_carve_kind, InnerDiskScript.CarveKind.POLYGON)


## Lints the silent-.tres-strip / UID-mismatch failure mode: a broken
## ext_resource resolves to null with no error at all (godot-workflow.md).
func test_every_archetype_references_a_standalone_shape() -> void:
	for arch_name in ["strength", "dexterity", "intelligence", "wisdom", "perception", "constitution"]:
		var arch: Archetype = load("res://archetypes/%s.tres" % arch_name)
		assert_not_null(arch, "%s.tres loads" % arch_name)
		assert_not_null(arch.carve_shape, "%s.tres carries a carve_shape" % arch_name)
		assert_true(arch.carve_shape is PolygonCarveShape, "%s carves a polygon" % arch_name)
		assert_ne(arch.carve_shape.resource_path, "",
			"%s's shape is a standalone .tres, not an inline sub_resource" % arch_name)
