extends GutTest
## ShadingStyle (#16 foundation): one shared shading source replaces the
## composite's old imperative per-property fan-out in _sync_shared(). Guards the
## contract — composite hands ONE object to every shaded child, and `changed`
## re-pushes — so a future consumer added with `child.shading = _shading` can't
## silently drift.

const CompositeScene := preload("res://skill_node/visuals/node_visuals_composite.tscn")
const DiskScene := preload("res://skill_node/visuals/inner_disk.tscn")


func test_shading_style_emits_changed_on_set() -> void:
	var style := ShadingStyle.new()
	watch_signals(style)
	style.tint_color = Color(1.0, 0.0, 0.0)
	assert_signal_emitted(style, "changed", "assigning a field emits changed")


func test_consumer_applies_shading_on_assign_and_on_change() -> void:
	var disk = add_child_autofree(DiskScene.instantiate())
	await get_tree().process_frame

	var style := ShadingStyle.new()
	style.tint_color = Color(0.2, 0.4, 0.6)
	style.allocated = true
	disk.shading = style
	assert_eq(disk.tint_color, Color(0.2, 0.4, 0.6), "assign pushes values in")
	assert_true(disk.allocated, "assign pushes allocated in")

	style.tint_color = Color(0.9, 0.1, 0.1)
	assert_eq(disk.tint_color, Color(0.9, 0.1, 0.1), "changed signal re-pushes")


func test_composite_shares_one_shading_across_shaded_children() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame

	var disk = comp.get_node("%InnerDisk")
	var weld = disk.get_node("%WeldSymbol")
	var rim = comp.get_node("%RimRing")
	assert_not_null(disk.shading, "InnerDisk received a shading source")
	assert_same(disk.shading, weld.shading, "WeldSymbol (composed inside InnerDisk) shares the SAME object")
	assert_same(disk.shading, rim.shading, "RimRing shares the SAME object")


func test_composite_tint_propagates_to_shaded_children() -> void:
	var comp = add_child_autofree(CompositeScene.instantiate())
	await get_tree().process_frame

	comp.entity_tint = Color(0.1, 0.7, 0.3)
	var disk = comp.get_node("%InnerDisk")
	var weld = disk.get_node("%WeldSymbol")
	assert_eq(disk.tint_color, Color(0.1, 0.7, 0.3), "disk tint follows composite's entity_tint")
	assert_eq(weld.tint_color, Color(0.1, 0.7, 0.3), "weld tint follows composite's entity_tint")
